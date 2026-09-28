import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/ability.dart';
import 'package:hidden_eleven/features/game/models/chemistry_vars.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/game/widgets/abilities_help.dart';
import 'package:hidden_eleven/features/game/widgets/panel_header.dart';
import 'package:hidden_eleven/features/lobby/room_provider.dart';

/// Full-screen takeover for the `ability_draft` phase: a face-down deck the
/// players pick from in turn order. Each player's pick is secret — only the
/// local player ever sees their own revealed card.
class AbilityDraftScreen extends ConsumerStatefulWidget {
  const AbilityDraftScreen({
    super.key,
    required this.game,
    required this.localPlayerId,
    this.connected = true,
  });

  final GameState game;
  final String? localPlayerId;

  /// False while the socket is reconnecting/disconnected. Disables card taps
  /// so a pick never gets sent into a connection that isn't confirmed
  /// healthy — the caller (game_screen.dart) already shows a top-level
  /// "Reconnecting…"/"Connection lost" banner/dialog for visibility; this is
  /// the matching action-gate, mirroring the same `connected` pattern
  /// `SubsPanel` already uses for the same reason.
  final bool connected;

  @override
  ConsumerState<AbilityDraftScreen> createState() => _AbilityDraftScreenState();
}

class _AbilityDraftScreenState extends ConsumerState<AbilityDraftScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dealController;

  @override
  void initState() {
    super.initState();
    _dealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _dealController.dispose();
    super.dispose();
  }

  String _nameOf(String? playerId) {
    if (playerId == null) return '—';
    final p = widget.game.players.where((p) => p.id == playerId).firstOrNull;
    return p?.displayName ?? '—';
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.game.abilityDraft;
    final myAbility = widget.game.myAbility;
    if (draft == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isMyTurn = draft.currentPickerId == widget.localPlayerId;
    final hasPicked = myAbility != null;
    final pickedCount = draft.cards.where((c) => c.isPicked).length;
    // No current picker → everyone has chosen; we're in the brief reveal window
    // before the draft starts (lets the last picker see their card).
    final allChosen = draft.currentPickerId == null;

    return Scaffold(
      backgroundColor: HETheme.pfBgVoid,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerRight,
                    child: AbilitiesHelpButton(),
                  ),
                  PanelHeader(
                    icon: Icons.auto_awesome_rounded,
                    eyebrow: 'ABILITY DRAFT',
                    title: allChosen
                        ? 'Everyone has chosen — starting draft…'
                        : hasPicked
                        ? 'Card locked in — waiting for others…'
                        : isMyTurn
                        ? 'Your turn — choose a card'
                        : 'Waiting for ${_nameOf(draft.currentPickerId)} to choose…',
                    emphasized: isMyTurn || allChosen,
                  ),
                  const SizedBox(height: 22),

                  // The face-down deck.
                  LayoutBuilder(
                    builder: (ctx, box) {
                      const gap = 12.0;
                      final n = draft.cards.length;
                      final cols = n <= 3 ? n : (n <= 8 ? 4 : 5);
                      final cardW = ((box.maxWidth - gap * (cols - 1)) / cols)
                          .clamp(76.0, 140.0);
                      return Wrap(
                        alignment: WrapAlignment.center,
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (var i = 0; i < draft.cards.length; i++)
                            _DealtCard(
                              controller: _dealController,
                              index: i,
                              total: draft.cards.length,
                              child: _PoolCard(
                                card: draft.cards[i],
                                width: cardW,
                                isMine:
                                    draft.cards[i].pickedBy ==
                                    widget.localPlayerId,
                                takenByName: draft.cards[i].isPicked
                                    ? _nameOf(draft.cards[i].pickedBy)
                                    : null,
                                enabled:
                                    isMyTurn &&
                                    !hasPicked &&
                                    !draft.cards[i].isPicked &&
                                    widget.connected,
                                onTap: () => ref
                                    .read(roomProvider.notifier)
                                    .pickAbility(draft.cards[i].id),
                              ),
                            ),
                        ],
                      );
                    },
                  ),

                  // Your revealed card, once picked.
                  if (myAbility != null) ...[
                    const SizedBox(height: 26),
                    _YourCardReveal(type: myAbility.type),
                  ],

                  const SizedBox(height: 24),
                  _ProgressRow(picked: pickedCount, total: draft.poolCount),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Deal-in entrance animation wrapper ──────────────────────────────────────

class _DealtCard extends StatelessWidget {
  const _DealtCard({
    required this.controller,
    required this.index,
    required this.total,
    required this.child,
  });
  final AnimationController controller;
  final int index;
  final int total;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final start = total <= 1 ? 0.0 : (index / total) * 0.5;
        final t = ((controller.value - start) / (1 - start)).clamp(0.0, 1.0);
        final eased = Curves.easeOutBack.transform(t);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - eased) * 28),
            child: Transform.scale(scale: 0.7 + 0.3 * eased, child: child),
          ),
        );
      },
      child: child,
    );
  }
}

// ── Pool card (face-down back, or taken state) ──────────────────────────────

class _PoolCard extends StatelessWidget {
  const _PoolCard({
    required this.card,
    required this.width,
    required this.isMine,
    required this.takenByName,
    required this.enabled,
    required this.onTap,
  });
  final AbilityCardInfo card;
  final double width;
  final bool isMine;
  final String? takenByName;
  final bool enabled;
  final VoidCallback onTap;

  // Same colour language as the Sealed Dossier: gold marks "your secret
  // card", violet marks "you may act on this now" — matching the hidden-pick
  // deck rather than the old generic emerald ring, so the two secret-card
  // moments in the game read as one design.
  @override
  Widget build(BuildContext context) {
    final ringColor = isMine
        ? HETheme.pfGold
        : (enabled ? HETheme.pfAccentViolet : HETheme.pfBorder);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: width,
        child: AspectRatio(
          aspectRatio: 3 / 4.2,
          child: Opacity(
            opacity: card.isPicked && !isMine ? 0.5 : 1,
            child: Container(
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(
                      ringColor.withValues(alpha: 0.05),
                      HETheme.pfSurfaceRaised,
                    ),
                    HETheme.pfSurfaceDeep,
                  ],
                ),
                borderRadius: BorderRadius.circular(HEShape.rMd),
                border: Border.all(
                  color: ringColor.withValues(
                    alpha: enabled || isMine ? 0.85 : 0.4,
                  ),
                  width: enabled || isMine ? 2 : 1.2,
                ),
                boxShadow: (enabled || isMine)
                    ? [
                        BoxShadow(
                          color: ringColor.withValues(alpha: 0.32),
                          blurRadius: 16,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: _BackPatternPainter(color: ringColor)),
                  Center(
                    child: Icon(
                      isMine
                          ? Icons.check_circle_rounded
                          : Icons.help_outline_rounded,
                      color: ringColor.withValues(alpha: isMine ? 0.9 : 0.4),
                      size: width * 0.34,
                    ),
                  ),
                  if (takenByName != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 6,
                      child: Text(
                        isMine ? 'YOU' : takenByName!,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: HETheme.pfTextSecondary,
                          fontSize: (width * 0.1).clamp(8.0, 11.0),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BackPatternPainter extends CustomPainter {
  const _BackPatternPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.05)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    const spacing = 12.0;
    for (double d = -size.height; d < size.width + size.height; d += spacing) {
      canvas.drawLine(
        Offset(d, 0),
        Offset(d + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BackPatternPainter old) => old.color != color;
}

// ── Your revealed card (one-time 3D flip) ───────────────────────────────────

class _YourCardReveal extends StatelessWidget {
  const _YourCardReveal({required this.type});
  final AbilityType type;

  @override
  Widget build(BuildContext context) {
    final meta = AbilityMeta.of(type);
    return Column(
      children: [
        Text(
          'YOUR CARD',
          style: TextStyle(
            color: HETheme.pfTextMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 10),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 750),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) {
            // Flip the front face in from edge-on: rotate pi/2 → 0 while the
            // face stays readable (no mirroring) at the resting angle.
            final showFront = t > 0.5;
            final angle = showFront
                ? (1 - t) *
                      math
                          .pi // pi/2 → 0 as t goes 0.5 → 1
                : (0.5 - t) * math.pi +
                      math.pi / 2; // pi → pi/2 as t goes 0 → 0.5
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0015)
                ..rotateY(angle),
              child: showFront
                  ? AbilityCardFront(meta: meta)
                  : _CardBackPlaceholder(),
            );
          },
        ),
        const SizedBox(height: 10),
        Text(
          'Keep it secret. You’ll use or discard it after the draft.',
          style: TextStyle(color: HETheme.pfTextMuted, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _CardBackPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      height: 210,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [HETheme.pfSurfaceRaised, HETheme.pfSurfaceDeep],
        ),
        borderRadius: BorderRadius.circular(HEShape.rLg),
        border: Border.all(color: HETheme.pfGold.withValues(alpha: 0.5)),
      ),
    );
  }
}

class AbilityCardFront extends StatelessWidget {
  const AbilityCardFront({required this.meta});
  final AbilityMeta meta;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // Blended toward the Night Tactics plum rather than pure black, so
        // every ability's own colour (server-defined, left untouched) still
        // reads as sitting on the same surface family as the rest of the app.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(meta.color, HETheme.pfSurfaceRaised, 0.55)!,
            Color.lerp(meta.color, HETheme.pfBgVoid, 0.82)!,
          ],
        ),
        borderRadius: BorderRadius.circular(HEShape.rLg),
        border: Border.all(color: meta.color, width: 2),
        boxShadow: [
          BoxShadow(
            color: meta.color.withValues(alpha: 0.45),
            blurRadius: 22,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: meta.color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: meta.color.withValues(alpha: 0.6)),
            ),
            child: Icon(meta.icon, color: meta.color, size: 34),
          ),
          const SizedBox(height: 12),
          Text(
            meta.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: meta.color,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            ChemistryVars.resolve(meta.description),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: HETheme.pfTextPrimary,
              fontSize: 11.5,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Persistent "your ability" chip (shown beside the player all game) ────────

/// A compact pill showing the local player's secret ability for the rest of the
/// game. Tapping it opens the full card. Render it in the game app bar.
class AbilityChip extends StatelessWidget {
  const AbilityChip({super.key, required this.type});
  final AbilityType type;

  @override
  Widget build(BuildContext context) {
    final meta = AbilityMeta.of(type);
    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.72),
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AbilityCardFront(meta: meta),
              const SizedBox(height: 12),
              const Text(
                'Your secret card — keep it to yourself.',
                style: TextStyle(color: HETheme.pfTextMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: meta.color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(HEShape.rPill),
          border: Border.all(color: meta.color.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(meta.icon, color: meta.color, size: 15),
            const SizedBox(width: 5),
            Text(
              meta.name.replaceAll(' Card', ''),
              style: TextStyle(
                color: meta.color,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Progress row ────────────────────────────────────────────────────────────

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.picked, required this.total});
  final int picked;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$picked / $total players have chosen',
          style: const TextStyle(color: HETheme.pfTextMuted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(HEShape.rPill),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : picked / total,
            minHeight: 6,
            backgroundColor: HETheme.pfBorder,
            valueColor: const AlwaysStoppedAnimation(HETheme.pfAccentViolet),
          ),
        ),
      ],
    );
  }
}
