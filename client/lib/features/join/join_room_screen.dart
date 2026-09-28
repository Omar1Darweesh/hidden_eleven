import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hidden_eleven/app/he_motion.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/app/routes.dart';
import 'package:hidden_eleven/features/game/game_provider.dart';
import 'package:hidden_eleven/features/lobby/room_provider.dart';
import 'package:hidden_eleven/shared/widgets/first_touch_layout.dart';
import 'package:hidden_eleven/shared/widgets/he_button.dart';
import 'package:hidden_eleven/shared/widgets/he_logo_mark.dart';
import 'package:hidden_eleven/shared/widgets/hero_entrance.dart';
import 'package:hidden_eleven/shared/widgets/matchday_background.dart';
import 'package:hidden_eleven/shared/widgets/primary_cta_glow.dart';
import 'package:hidden_eleven/shared/widgets/screen_entrance.dart';

enum _JoinState { idle, loading, pending, rejected }

class JoinRoomScreen extends ConsumerStatefulWidget {
  const JoinRoomScreen({super.key, required this.displayName});

  final String displayName;

  @override
  ConsumerState<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends ConsumerState<JoinRoomScreen> {
  final _codeController = TextEditingController();
  String? _codeError;
  _JoinState _state = _JoinState.idle;

  @override
  void initState() {
    super.initState();

    // Server error while joining (not found, full, started, kicked, etc.)
    ref.listenManual(serverErrorProvider, (_, next) {
      next.whenData((err) {
        if (!mounted) return;
        // Ignore stale cached errors that arrive before the player submits.
        if (_state != _JoinState.loading) return;
        setState(() {
          _state = _JoinState.idle;
          _codeError = switch (err.code) {
            'ROOM_NOT_FOUND' => 'Room not found. Check the code and try again.',
            'ROOM_FULL' => 'This room is full.',
            'ROOM_STARTED' => 'This game has already started.',
            'KICKED' => 'You were removed from this room and cannot rejoin.',
            'SPECTATORS_FULL' =>
              'This room already has the maximum number of spectators.',
            _ => 'Something went wrong. Try again.',
          };
        });
      });
    });

    // Server put our request in a pending queue (room is locked).
    ref.listenManual(joinPendingProvider, (_, next) {
      next.whenData((_) {
        if (!mounted) return;
        setState(() => _state = _JoinState.pending);
      });
    });

    // Host rejected our request.
    ref.listenManual(joinRejectedProvider, (_, next) {
      next.whenData((_) {
        if (!mounted) return;
        setState(() {
          _state = _JoinState.rejected;
          _codeError = null;
        });
      });
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    if (_codeError != null) setState(() => _codeError = null);
    if (_state == _JoinState.rejected) {
      setState(() => _state = _JoinState.idle);
    }
  }

  bool _validate() {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _codeError = 'Enter a room code');
      return false;
    }
    if (code.length != 6) {
      setState(() => _codeError = 'Room code must be 6 letters');
      return false;
    }
    return true;
  }

  void _joinRoom() {
    if (!_validate()) return;
    setState(() {
      _state = _JoinState.loading;
      _codeError = null;
    });
    final code = _codeController.text.trim().toUpperCase();
    ref.read(roomProvider.notifier).joinRoom(code, widget.displayName);
  }

  /// First spectator entry point (see MULTIPLAYER_ROOMS_DESIGN.md /
  /// FLUTTER_CLIENT_AUDIT.md). Unlike _joinRoom, the server accepts this even
  /// after the room has started — watching a live game is the primary real
  /// use case, not just an empty lobby. Routing to the right screen
  /// afterwards is handled by the same roomProvider listener below.
  void _spectateRoom() {
    if (!_validate()) return;
    setState(() {
      _state = _JoinState.loading;
      _codeError = null;
    });
    final code = _codeController.text.trim().toUpperCase();
    ref.read(roomProvider.notifier).spectateRoom(code, widget.displayName);
  }

  void _cancelRequest() {
    setState(() => _state = _JoinState.idle);
    // Optionally disconnect so we stop waiting — server will clean up on disconnect.
    // We don't send leave_permanently here because we were never added to the room.
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(roomProvider, (_, room) {
      if (room == null || !mounted) return;
      // A spectate_room ack for an already-started game arrives with
      // gameProvider already populated (the server pushes game_state
      // immediately) — go straight to the game screen instead of the lobby.
      // joinRoom can never hit this branch itself: the server rejects
      // joining an already-started room (ROOM_STARTED) before this listener
      // ever fires, so existing player routing is completely unaffected.
      if (ref.read(gameProvider) != null) {
        context.goNamed(Routes.game, pathParameters: {'roomCode': room.code});
      } else {
        context.goNamed(Routes.lobby, pathParameters: {'roomCode': room.code});
      }
    });

    final bool canBack =
        _state != _JoinState.loading && _state != _JoinState.pending;

    return Scaffold(
      backgroundColor: HETheme.pfBgVoid,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: canBack ? () => context.pop() : null,
        ),
        title: const Text('Join a Room'),
      ),
      body: Stack(
        children: [
          const MatchdayBackground(),
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: FirstTouchLayout(
                  child: ScreenEntrance(
                    // Cross-fades between idle/pending/rejected instead of a
                    // hard cut — those are real state changes (request sent,
                    // host responded) that deserve to read as a transition, not
                    // a flicker.
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, 0.03),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: switch (_state) {
                        _JoinState.pending => _PendingApprovalCard(
                          key: const ValueKey('pending'),
                          onCancel: _cancelRequest,
                        ),
                        _JoinState.rejected => _RejectedCard(
                          key: const ValueKey('rejected'),
                          onRetry: () =>
                              setState(() => _state = _JoinState.idle),
                        ),
                        _ => _JoinForm(
                          key: const ValueKey('form'),
                          displayName: widget.displayName,
                          codeController: _codeController,
                          codeError: _codeError,
                          isLoading: _state == _JoinState.loading,
                          onChanged: _onChanged,
                          onJoin: _joinRoom,
                          onSpectate: _spectateRoom,
                        ),
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Join form ─────────────────────────────────────────────────────────────────

class _JoinForm extends StatelessWidget {
  const _JoinForm({
    super.key,
    required this.displayName,
    required this.codeController,
    required this.codeError,
    required this.isLoading,
    required this.onChanged,
    required this.onJoin,
    required this.onSpectate,
  });

  final String displayName;
  final TextEditingController codeController;
  final String? codeError;
  final bool isLoading;
  final ValueChanged<String> onChanged;
  final VoidCallback onJoin;

  /// First minimal spectator entry point — see MULTIPLAYER_ROOMS_DESIGN.md.
  final VoidCallback onSpectate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Hero header ──────────────────────────────────────────────────────
        HeroEntrance(child: _JoinHeroHeader(displayName: displayName)),

        const SizedBox(height: 28),

        // ── Room code entry ──────────────────────────────────────────────────
        _RoomCodeEntry(
          controller: codeController,
          error: codeError,
          isLoading: isLoading,
          onChanged: onChanged,
          onSubmit: onJoin,
        ),

        const SizedBox(height: 24),

        // ── CTA ──────────────────────────────────────────────────────────────
        if (isLoading)
          const _JoiningSpinner()
        else ...[
          PrimaryCtaGlow(
            intensity: 0.16,
            child: HEButton(
              label: 'Join Room',
              icon: Icons.login_rounded,
              onPressed: onJoin,
            ),
          ),
          const SizedBox(height: 10),
          HEButton(
            label: 'Watch Only',
            icon: Icons.visibility_rounded,
            variant: HEButtonVariant.ghost,
            onPressed: onSpectate,
          ),
        ],
      ],
    );
  }
}

// ── Join hero header ──────────────────────────────────────────────────────────

class _JoinHeroHeader extends StatelessWidget {
  const _JoinHeroHeader({required this.displayName});
  final String displayName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(HETheme.spaceXxl),
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceDeep.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(HETheme.radiusLg),
        border: Border.all(color: HETheme.pfAccentViolet.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: HETheme.pfAccentViolet.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Real Hidden Eleven logo — consistent brand anchor across all entry
          // screens (same compact treatment as the Host screen).
          const HELogoMark(height: 72, compact: true),
          const SizedBox(height: 16),
          Text(
            'Enter the Room Code',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: HETheme.pfTextPrimary,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(
                color: HETheme.pfTextSecondary,
                fontSize: 13,
              ),
              children: [
                const TextSpan(text: 'Joining as '),
                TextSpan(
                  text: displayName,
                  style: const TextStyle(
                    color: HETheme.pfAccentViolet,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const TextSpan(text: '  ·  Get the code from your host.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Room code entry ───────────────────────────────────────────────────────────

/// Elevated room code field — large letters, thick border, distinctive
/// premium feel that makes the code feel important, not generic.
///
/// Overrides every one of `TextField`'s own border states with
/// `InputBorder.none` (the surrounding container's border is authoritative
/// for the error-vs-normal look) — which also silently threw away the
/// field's default keyboard-focus indication. Converted to a stateful
/// widget so the container can restore that: a brighter cyan ring while the
/// field has keyboard focus, on top of the existing error-state border.
class _RoomCodeEntry extends StatefulWidget {
  const _RoomCodeEntry({
    required this.controller,
    required this.error,
    required this.isLoading,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String? error;
  final bool isLoading;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;

  @override
  State<_RoomCodeEntry> createState() => _RoomCodeEntryState();
}

class _RoomCodeEntryState extends State<_RoomCodeEntry>
    with SingleTickerProviderStateMixin {
  final _focusNode = FocusNode();
  bool _focused = false;
  int _lastLength = 0;

  /// Drives the per-keystroke scale pulse.
  ///
  /// This *must* stay a controller rather than a keyed [TweenAnimationBuilder]:
  /// the previous implementation rebuilt the pulse widget with a
  /// `ValueKey(_lastLength)` that changed on every character, which remounted
  /// the whole subtree — including this field's [TextField] — destroying its
  /// `EditableText` state and, on web, its browser input connection. The
  /// keyboard detached and focus was lost after every single character. A
  /// controller animates the same pulse without ever changing widget identity.
  ///
  /// Rests at 1.0 (settled) so the field is never left scaled up when idle;
  /// each keystroke restarts it from 0.0, giving the same 1.03 → 1.0 settle
  /// the old tween produced.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
    value: 1.0,
  );

  late final Animation<double> _pulseScale = Tween<double>(
    begin: 1.03,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _focused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleChanged(String value) {
    // A brief scale-pulse per keystroke — purely cosmetic feedback that a
    // letter registered, skipped entirely under reduced motion rather than
    // shortened, since there's nothing here that carries state information
    // the way a real transition would.
    if (value.length != _lastLength && !HEMotion.reduced(context)) {
      _pulse.forward(from: 0);
    }
    _lastLength = value.length;
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.error != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Label
        Row(
          children: [
            Container(
              width: 3,
              height: 12,
              decoration: BoxDecoration(
                color: HETheme.pfAccentViolet,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'ROOM CODE',
              style: TextStyle(
                color: HETheme.pfAccentViolet,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // The code input box — deliberately distinct from a standard text field
        AnimatedBuilder(
          animation: _pulseScale,
          builder: (context, child) =>
              Transform.scale(scale: _pulseScale.value, child: child),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: HETheme.pfSurfaceDeep.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(HETheme.radiusLg),
              border: Border.all(
                color: hasError
                    ? HETheme.pfDanger.withValues(alpha: 0.70)
                    : HETheme.pfAccentViolet.withValues(
                        alpha: _focused ? 0.65 : 0.30,
                      ),
                width: _focused && !hasError ? 2 : 1.5,
              ),
              boxShadow: hasError
                  ? [
                      BoxShadow(
                        color: HETheme.pfDanger.withValues(alpha: 0.08),
                        blurRadius: 12,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: HETheme.pfAccentViolet.withValues(
                          alpha: _focused ? 0.14 : 0.06,
                        ),
                        blurRadius: 12,
                      ),
                    ],
            ),
            // The 6 widely-spaced (letterSpacing: 12) 32px glyphs already
            // fill a 360px-wide field at Standard scale — left to the app's
            // text-scale multiplier on top of that (Large/XL can reach
            // 1.3x), 6 characters would overflow a phone-width screen.
            // This field's letters are already large and legible by
            // design, so it opts out of the ambient text scaler entirely
            // rather than growing further; everything else on this screen
            // (labels, hints, buttons) still scales normally.
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.noScaling),
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                onChanged: _handleChanged,
                onSubmitted: (_) => widget.onSubmit(),
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                enabled: !widget.isLoading,
                autofocus: true,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
                ],
                style: const TextStyle(
                  color: HETheme.pfAccentViolet,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 12,
                  height: 1.0,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: '······',
                  hintStyle: TextStyle(
                    color: HETheme.pfTextSecondary.withValues(alpha: 0.25),
                    fontSize: 32,
                    letterSpacing: 12,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                  counterText: '',
                  // Override theme borders so the container border is
                  // authoritative.
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                ),
              ),
            ),
          ),
        ),
        // Error message
        if (hasError) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: HETheme.pfDanger,
                size: 14,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.error!,
                  style: const TextStyle(color: HETheme.pfDanger, fontSize: 12),
                ),
              ),
            ],
          ),
        ] else ...[
          const SizedBox(height: 8),
          const Text(
            '6-letter code  ·  letters only',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: HETheme.pfTextMuted,
              fontSize: 11,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Joining spinner ───────────────────────────────────────────────────────────

class _JoiningSpinner extends StatelessWidget {
  const _JoiningSpinner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: HETheme.pfAccentViolet.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(HETheme.radiusMd),
        border: Border.all(color: HETheme.pfAccentViolet.withValues(alpha: 0.15)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              color: HETheme.pfAccentViolet,
              strokeWidth: 2.5,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Joining room…',
            style: TextStyle(
              color: HETheme.pfTextSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pending approval card ─────────────────────────────────────────────────────

class _PendingApprovalCard extends StatelessWidget {
  const _PendingApprovalCard({super.key, required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(HETheme.spaceXxl),
          decoration: BoxDecoration(
            color: HETheme.pfSurfaceDeep.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(HETheme.radiusLg),
            border: Border.all(
              color: HETheme.pfAccentViolet.withValues(alpha: 0.22),
            ),
          ),
          child: Column(
            children: [
              // Pulse ring
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: HETheme.pfAccentViolet.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(
                      color: HETheme.pfAccentViolet,
                      strokeWidth: 2.5,
                    ),
                  ),
                  const Icon(
                    Icons.hourglass_top_rounded,
                    color: HETheme.pfAccentViolet,
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Waiting for Approval',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'The host has been notified.\nYour request will be accepted or declined shortly.',
                style: const TextStyle(
                  color: HETheme.pfTextSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        HEButton(
          label: 'Cancel Request',
          variant: HEButtonVariant.ghost,
          onPressed: onCancel,
        ),
      ],
    );
  }
}

// ── Rejected card ─────────────────────────────────────────────────────────────

class _RejectedCard extends StatelessWidget {
  const _RejectedCard({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(HETheme.spaceXxl),
          decoration: BoxDecoration(
            color: HETheme.pfDanger.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(HETheme.radiusLg),
            border: Border.all(color: HETheme.pfDanger.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: HETheme.pfDanger.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(HETheme.radiusLg),
                  border: Border.all(
                    color: HETheme.pfDanger.withValues(alpha: 0.35),
                  ),
                ),
                child: const Icon(
                  Icons.block_rounded,
                  color: HETheme.pfDanger,
                  size: 28,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Request Declined',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'The host declined your request to join this room.',
                style: TextStyle(
                  color: HETheme.pfTextSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        HEButton(
          label: 'Try a Different Room',
          icon: Icons.refresh_rounded,
          variant: HEButtonVariant.secondary,
          onPressed: onRetry,
        ),
      ],
    );
  }
}
