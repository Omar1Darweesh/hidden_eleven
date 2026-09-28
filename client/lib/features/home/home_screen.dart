import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/app/routes.dart';
import 'package:hidden_eleven/features/home/widgets/current_room_card.dart';
import 'package:hidden_eleven/features/lobby/room_provider.dart';
import 'package:hidden_eleven/shared/ads/ad_config.dart';
import 'package:hidden_eleven/shared/ads/side_ad_rail.dart';
import 'package:hidden_eleven/shared/providers/local_presence_provider.dart';
import 'package:hidden_eleven/shared/providers/local_spectator_presence_provider.dart';
import 'package:hidden_eleven/shared/widgets/first_touch_layout.dart';
import 'package:hidden_eleven/shared/widgets/he_button.dart';
import 'package:hidden_eleven/shared/widgets/he_card.dart';
import 'package:hidden_eleven/shared/widgets/he_logo_mark.dart';
import 'package:hidden_eleven/shared/widgets/he_text_field.dart';
import 'package:hidden_eleven/shared/widgets/matchday_background.dart';
import 'package:hidden_eleven/shared/widgets/primary_cta_glow.dart';
import 'package:hidden_eleven/shared/widgets/provider_credit.dart';
import 'package:hidden_eleven/shared/widgets/screen_entrance.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  String? _nameError;
  bool _jumpingIn = false;

  late final AnimationController _entranceController;
  late final Animation<double> _entranceFade;
  late final Animation<Offset> _entranceSlide;

  /// Cinematic logo entrance: scales in from 90% with a single, brief
  /// overshoot settle (`easeOutBack`) rather than a linear grow — reads as
  /// "arriving with weight," once, not a repeating bounce. Driven by the
  /// same controller as the fade/slide above so it's still skipped
  /// instantly under reduced motion.
  late final Animation<double> _logoScale;

  @override
  void initState() {
    super.initState();

    // Home is the very first thing every visitor sees, and previously
    // rendered fully formed with zero motion — this settles the hero
    // (logo/tagline/pillars) in first, then the action zone follows via its
    // own delayed `ScreenEntrance` below — a staggered logo → chips →
    // action-zone entry, started in didChangeDependencies once
    // MediaQuery/reduced-motion is available.
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _entranceFade = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _entranceSlide = Tween(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(_entranceFade);
    _logoScale = Tween(begin: 0.90, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutBack),
    );
  }

  bool _entranceStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_entranceStarted) {
      _entranceStarted = true;
      if (MediaQuery.of(context).disableAnimations) {
        _entranceController.value = 1.0;
      } else {
        _entranceController.forward();
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  String get _trimmedName => _nameController.text.trim();

  void _onNameChanged(String _) {
    if (_nameError != null) setState(() => _nameError = null);
  }

  bool _validate() {
    if (_trimmedName.isEmpty) {
      setState(() => _nameError = 'Enter a display name to continue');
      return false;
    }
    if (_trimmedName.length < 2) {
      setState(() => _nameError = 'Name must be at least 2 characters');
      return false;
    }
    return true;
  }

  void _hostRoom() {
    if (!_validate()) return;
    context.pushNamed(Routes.hostRoom, extra: _trimmedName);
  }

  void _joinRoom() {
    if (!_validate()) return;
    context.pushNamed(Routes.joinRoom, extra: _trimmedName);
  }

  /// Solo mode: opens the exact same host-settings screen as "Host a Room" —
  /// leagues, tournament, timers, formation — with AI Opponents pre-set to 1,
  /// rather than a bespoke flow that skips those settings entirely. The host
  /// can still raise/lower the bot count or add real players there too; solo
  /// and "host with bots" are the same screen, not two separate modes.
  void _playSolo() {
    if (!_validate()) return;
    context.pushNamed(
      Routes.hostRoom,
      extra: (displayName: _trimmedName, botCount: 1),
    );
  }

  void _jumpIn() {
    // Read the token straight from storage-backed presence at tap time. A
    // seat with no reconnect token can never be resumed (check_presence would
    // fail validation), so clear it and tell the player to start fresh rather
    // than spin forever.
    final token = ref.read(localPresenceProvider)?.reconnectToken;
    if (token == null || token.isEmpty) {
      _showToast('Session expired. Please join a new room.');
      ref.read(localPresenceProvider.notifier).clear();
      return;
    }
    setState(() => _jumpingIn = true);
    ref.read(roomProvider.notifier).jumpIn();
  }

  void _leaveGamePermanently() {
    setState(() => _jumpingIn = false);
    ref.read(roomProvider.notifier).leaveGamePermanently();
  }

  void _jumpInAsSpectator() {
    final token = ref.read(localSpectatorPresenceProvider)?.reconnectToken;
    if (token == null || token.isEmpty) {
      _showToast('Session expired. Please spectate again.');
      ref.read(localSpectatorPresenceProvider.notifier).clear();
      return;
    }
    setState(() => _jumpingIn = true);
    ref.read(roomProvider.notifier).jumpInAsSpectator();
  }

  void _stopWatchingFromHome() {
    // Not connected to that room right now — nothing to tell the server,
    // just drop the local seat so the resume card disappears.
    ref.read(localSpectatorPresenceProvider.notifier).clear();
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final presence = ref.watch(localPresenceProvider);
    final hasActiveGame = presence != null;
    // Player presence always wins — see room_provider.dart's _savePresence,
    // which clears any lingering spectator presence once a real player seat
    // is saved, so this should only ever matter transiently. Checking it
    // here too means HomeScreen never shows both resume cards at once.
    final spectatorPresence = hasActiveGame
        ? null
        : ref.watch(localSpectatorPresenceProvider);
    final hasActiveSpectating = spectatorPresence != null;

    ref.listen(roomProvider, (_, room) {
      if (room != null && _jumpingIn && mounted) {
        setState(() => _jumpingIn = false);
        if (room.isStarted) {
          context.pushNamed(
            Routes.game,
            pathParameters: {'roomCode': room.code},
          );
        } else {
          context.pushNamed(
            Routes.lobby,
            pathParameters: {'roomCode': room.code},
          );
        }
      }
    });

    ref.listen(serverErrorProvider, (_, next) {
      next.whenData((err) {
        if (!mounted) return;
        if (_jumpingIn) setState(() => _jumpingIn = false);
        switch (err.code) {
          case 'NOT_FOUND':
          case 'INVALID_TOKEN':
            // A rejected check_presence/spectator_reconnect (this screen's
            // own Jump In / Resume Watching, or an auto-retry that happened
            // to resolve while this screen was frontmost). Handled
            // centrally by RoomNotifier._handleReconnectRejection, which
            // wipes local state and triggers sessionDesyncedProvider —
            // HiddenElevenApp's root builder shows the blocking
            // SessionDesyncedScreen over this screen the instant that
            // fires, so no toast is needed here (a toast racing a full-
            // screen takeover a moment later was also just confusing UX).
            break;
          case 'KICKED':
            _showToast('You were removed from this room.');
          default:
            break;
        }
      });
    });

    // The presence provider loads asynchronously from SharedPreferences
    // (see local_presence_provider.dart) — before it resolves, `presence`
    // reads as null the same as "definitely no active game," which would
    // otherwise let the resume card flash in a frame late. This brief
    // skeleton only shows while that load is genuinely in flight.
    final presenceReady = ref.read(localPresenceProvider.notifier).ready;

    return Scaffold(
      body: SideAdRail(
        slotId: AdConfig.homeSideSlot,
        child: Stack(
          children: [
            const MatchdayBackground(showClassifiedGlow: true),
            SafeArea(
              child: Stack(
                children: [
                  // Soft brand halo behind the logo — confined to hero area.
                  const Positioned(
                    top: -40,
                    left: 0,
                    right: 0,
                    child: _HeroGlow(),
                  ),
                  // One page, no scrolling: `FittedBox` scales the whole
                  // hero+form column down to fit whatever viewport height is
                  // available (it only ever shrinks, via `scaleDown` — on a
                  // tall viewport the content just renders at its natural
                  // size, centered). Requires `mainAxisSize: min` on the
                  // Column below so FittedBox can measure its natural,
                  // unconstrained height.
                  Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: FadeTransition(
                        opacity: _entranceFade,
                        child: SlideTransition(
                          position: _entranceSlide,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: FirstTouchLayout(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Extra top breathing room so logo feels anchored.
                                  const SizedBox(height: 8),
                                  ScaleTransition(
                                    scale: _logoScale,
                                    child: const _BrandBlock(),
                                  ),
                                  const SizedBox(height: 28),

                                  if (!hasActiveGame && !hasActiveSpectating)
                                    FutureBuilder<void>(
                                      future: presenceReady,
                                      builder: (context, snapshot) {
                                        if (snapshot.connectionState ==
                                            ConnectionState.done) {
                                          return const SizedBox.shrink();
                                        }
                                        return const Padding(
                                          padding: EdgeInsets.only(bottom: 24),
                                          child: _ResumeCardSkeleton(),
                                        );
                                      },
                                    ),

                                  if (hasActiveGame) ...[
                                    const HESectionLabel('Active Game'),
                                    const SizedBox(height: 12),
                                    CurrentRoomCard(
                                      presence: presence,
                                      isJumpingIn: _jumpingIn,
                                      onJumpIn: _jumpIn,
                                      onLeave: _leaveGamePermanently,
                                    ),
                                    const SizedBox(height: 40),
                                  ],

                                  if (hasActiveSpectating) ...[
                                    const HESectionLabel('Spectating'),
                                    const SizedBox(height: 12),
                                    CurrentSpectatingCard(
                                      presence: spectatorPresence,
                                      isJumpingIn: _jumpingIn,
                                      onResume: _jumpInAsSpectator,
                                      onStopWatching: _stopWatchingFromHome,
                                    ),
                                    const SizedBox(height: 40),
                                  ],

                                  if (!hasActiveGame &&
                                      !hasActiveSpectating) ...[
                                    // Pitch-line divider transitions from brand hero to
                                    // action zone — a deliberate, restrained motif.
                                    const _PitchDivider(),
                                    const SizedBox(height: 32),

                                    // Staggered behind the hero's own entrance —
                                    // logo/tagline/pillars settle first, the action
                                    // zone follows ~120ms later. ScreenEntrance
                                    // already skips straight to the settled state
                                    // under reduced motion.
                                    ScreenEntrance(
                                      delay: const Duration(milliseconds: 120),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          const HESectionLabel('Display Name'),
                                          const SizedBox(height: 10),
                                          HETextField(
                                            controller: _nameController,
                                            hintText: 'Your name in the room',
                                            errorText: _nameError,
                                            onChanged: _onNameChanged,
                                            textInputAction:
                                                TextInputAction.done,
                                          ),
                                          const SizedBox(height: 24),

                                          // Host is the primary action, not a hidden/
                                          // reveal moment — cyan glow, per the app's
                                          // semantic-color rule (gold is reserved for
                                          // classified/hidden-pick contexts only).
                                          PrimaryCtaGlow(
                                            child: HEButton(
                                              label: 'Host a Room',
                                              icon: Icons
                                                  .add_circle_outline_rounded,
                                              onPressed: _hostRoom,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          HEButton(
                                            label: 'Join a Room',
                                            icon: Icons.login_rounded,
                                            variant: HEButtonVariant.secondary,
                                            onPressed: _joinRoom,
                                          ),
                                          const SizedBox(height: 12),
                                          // Solo entry point. Sits below the two
                                          // multiplayer options, and one tier lower in
                                          // visual weight (ghost, not secondary) —
                                          // playing another person is still the point
                                          // of the game, but this is the only path
                                          // that works for someone who arrives with
                                          // nobody to play against, which is most
                                          // first-time visitors.
                                          HEButton(
                                            label: 'Play vs AI',
                                            icon: Icons.smart_toy_outlined,
                                            variant: HEButtonVariant.ghost,
                                            onPressed: _playSolo,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 32),
                                    const _HowItWorks(),
                                    const SizedBox(height: 8),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // These MUST stay the last children of the Stack. A Stack
                  // hit-tests its children in reverse paint order (last child
                  // first), and the `Center` above is non-positioned, so it
                  // fills the whole Stack. Listed before it, these buttons still
                  // PAINT (the Center is transparent outside its FittedBox
                  // content) but would never receive a tap otherwise — that's
                  // the bug this ordering fixes.
                  // Sound mute now lives at the app root (GlobalSoundToggle,
                  // see app.dart) so it's reachable from every screen, not
                  // just this one — no per-screen copy needed here anymore.
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      icon: const Icon(Icons.help_outline_rounded),
                      color: HETheme.pfTextSecondary,
                      tooltip: 'How to Play',
                      onPressed: () => context.pushNamed(Routes.help),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Resume-card loading skeleton ────────────────────────────────────────────

/// Bridges the brief window while `localPresenceProvider` loads from
/// SharedPreferences — shown only until that load genuinely resolves (see
/// `_HomeScreenState.build`'s `presenceReady` future), never a fixed delay.
class _ResumeCardSkeleton extends StatelessWidget {
  const _ResumeCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceGlass.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(HETheme.radiusLg),
        border: Border.all(color: HETheme.pfBorder),
      ),
    );
  }
}

// ── Hero glow ─────────────────────────────────────────────────────────────────

/// Soft cyan halo confined to the hero area.
class _HeroGlow extends StatelessWidget {
  const _HeroGlow();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 340,
          height: 340,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                HETheme.pfAccentViolet.withValues(alpha: 0.14),
                HETheme.pfAccentViolet.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Brand block ───────────────────────────────────────────────────────────────

class _BrandBlock extends StatelessWidget {
  const _BrandBlock();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const HELogoMark(height: 168),
        const SizedBox(height: 24),

        // Wider divider line — more presence under the logo.
        Container(
          width: 48,
          height: 1.5,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                HETheme.pfAccentViolet.withValues(alpha: 0.0),
                HETheme.pfAccentViolet.withValues(alpha: 0.8),
                HETheme.pfAccentViolet.withValues(alpha: 0.0),
              ],
            ),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(height: 14),

        // Subtitle — slightly larger, heavier weight for stronger presence.
        Text(
          'Build your squad.\u2002Hide your hand.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: HETheme.pfTextSecondary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
            height: 1.35,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 22),

        // Feature chips — each chip now has a distinct accent that maps to
        // what it represents in gameplay:
        //   Draft     → cyan  (core session identity)
        //   Hidden    → gold  (mystery/tension, the premium secret)
        //   Chemistry → green (reward/scoring, the payoff)
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: const [
            _FeatureChip(
              label: 'Draft',
              icon: Icons.sports_soccer_rounded,
              color: HETheme.pfAccentViolet,
            ),
            _FeatureChip(
              label: 'Hidden Picks',
              icon: Icons.visibility_off_rounded,
              color: HETheme.pfGold,
            ),
            _FeatureChip(
              label: 'Chemistry',
              icon: Icons.auto_awesome_rounded,
              color: HETheme.pfSuccess,
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Provider attribution — credits OYO as the studio behind the game,
        // directly under the brand hero.
        const ProviderCredit(),
      ],
    );
  }
}

// ── Feature chip ──────────────────────────────────────────────────────────────

/// A single feature pill — slightly more structured than HEBadge, with a
/// tighter glow and a pill shape instead of a rounded rect.
class _FeatureChip extends StatelessWidget {
  const _FeatureChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.32), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color.withValues(alpha: 0.85)),
          const SizedBox(width: 5),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color.withValues(alpha: 0.90),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pitch divider ─────────────────────────────────────────────────────────────

/// A restrained decorative separator using a half-pitch arc motif.
/// Signals the transition from the brand hero zone to the action zone
/// without being heavy or distracting.
///
/// Deliberately just the halfway line now — no separate mini circle/dot/
/// arc motif of its own. The one real "center circle" on the page is the
/// large one already drawn in `MatchdayBackground`'s pitch-line geometry;
/// this divider used to draw a second, smaller, differently-positioned
/// circle that read as a mismatched duplicate rather than the same pitch.
/// A plain line here lets it pass through that same background circle
/// without competing with it.
class _PitchDivider extends StatelessWidget {
  const _PitchDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            HETheme.pfAccentViolet.withValues(alpha: 0.0),
            HETheme.pfAccentViolet.withValues(alpha: 0.22),
            HETheme.pfAccentViolet.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}

// ── How it works ──────────────────────────────────────────────────────────────

/// An integrated, borderless timeline section rather than a generic card —
/// a vertical connector line and numbered nodes, cleaner and more editorial
/// than a bordered explainer card. Condensed to exactly three concise
/// pillars (was four, more verbose steps) per the First Touch Experience
/// redesign: scouting, sealing, and the reveal are the three moments that
/// actually define this game to a first-time visitor.
class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    const steps = [
      _StepData(
        'Scout your XI',
        'Draft in turns from the pool — build your starting eleven.',
        Icons.sports_soccer_rounded,
        HETheme.pfAccentViolet,
      ),
      _StepData(
        'Seal your picks',
        'Hidden selections stay locked — no one sees your hand.',
        Icons.lock_outline_rounded,
        HETheme.pfGold,
      ),
      _StepData(
        'Reveal the tactics',
        'Picks unlock, chemistry counts, and the best squad wins.',
        Icons.emoji_events_outlined,
        HETheme.pfSuccess,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header row
        Row(
          children: [
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: HETheme.pfAccentViolet,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'HOW IT WORKS',
              style: TextStyle(
                color: HETheme.pfAccentViolet,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // One compact row of all three steps — deliberately not a vertical
        // timeline: three numbered pillars side by side take a fraction of
        // the height a stacked list would, which matters on a screen with
        // no scrolling to fall back on.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < steps.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: _StepColumn(step: steps[i], number: i + 1),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _StepData {
  const _StepData(this.title, this.subtitle, this.icon, this.color);
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
}

class _StepColumn extends StatelessWidget {
  const _StepColumn({required this.step, required this.number});
  final _StepData step;
  final int number;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NodeDot(color: step.color, number: number),
        const SizedBox(height: 8),
        Text(
          step.title,
          style: const TextStyle(
            color: HETheme.pfTextPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          step.subtitle,
          style: const TextStyle(
            color: HETheme.pfTextSecondary,
            fontSize: 10.5,
            height: 1.3,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ── Node dot ──────────────────────────────────────────────────────────────────

class _NodeDot extends StatelessWidget {
  const _NodeDot({required this.color, required this.number});
  final Color color;
  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.40), width: 1),
      ),
      child: Center(
        child: Text(
          '$number',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}
