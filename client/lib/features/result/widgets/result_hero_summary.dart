import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_motion.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/app/theme.dart' show HESpacing, HEShadows;
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/tournament/models/tournament_models.dart';

/// The hero section — the first thing a user reads. Answers "who won" and
/// "why" in one glance, and states plainly when the top spot is a shared
/// rank rather than implying a single winner where none exists.
///
/// Stateful purely for the entrance animation: the trophy pops in, the
/// content settles in behind it, and the local winner gets a one-shot
/// confetti burst — this is the single moment in the whole match that
/// deserves a payoff, and the content above was previously rendering fully
/// formed with no motion at all.
class ResultHeroSummary extends StatefulWidget {
  final GameState game;
  final String? localPlayerId;
  final TournamentAwardsModel? awards;

  const ResultHeroSummary({
    super.key,
    required this.game,
    required this.localPlayerId,
    this.awards,
  });

  @override
  State<ResultHeroSummary> createState() => _ResultHeroSummaryState();
}

class _ResultHeroSummaryState extends State<ResultHeroSummary>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _trophyScale;
  late final Animation<double> _contentFade;
  late final Animation<Offset> _contentSlide;
  bool _started = false;

  GameState get game => widget.game;
  String? get localPlayerId => widget.localPlayerId;
  TournamentAwardsModel? get awards => widget.awards;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    // Overshoots past 1.0 then settles — a linear scale-in reads as a UI
    // element appearing; the overshoot is what reads as the trophy "landing".
    _trophyScale = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.65, curve: Curves.elasticOut),
    );
    _contentFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 1.0, curve: Curves.easeOut),
    );
    _contentSlide = Tween(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(_contentFade);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Under reduced motion, jump straight to the settled end state instead
    // of animating in — this also means the confetti painter (which fades
    // to zero opacity as progress approaches 1.0) naturally paints nothing,
    // so no extra branching is needed there.
    if (HEMotion.reduced(context)) {
      _controller.value = 1.0;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<PlayerResult> get _winners {
    final players = game.result?.players ?? const <PlayerResult>[];
    if (players.isEmpty) return const [];
    var topRank = players.first.rank;
    for (final p in players) {
      if (p.rank < topRank) topRank = p.rank;
    }
    return players.where((p) => p.rank == topRank).toList();
  }

  String _displayName(PlayerResult w) {
    final p = game.players.where((pl) => pl.id == w.playerId).firstOrNull;
    return p?.displayName ?? w.displayName;
  }

  /// A genuine, data-driven explanation — never a placeholder line.
  String _winReason(PlayerResult winner) {
    final a = awards;
    if (a != null && winner.playerId == a.champion.participantId) {
      return 'Winning the cup final secured the top spot — the tournament '
          'champion bonus (+${a.pointsConfig.championPoints}) was decisive.';
    }
    final bonus = a?.pointsAwarded[winner.playerId] ?? 0;
    if (bonus > 0) {
      return 'Tournament bonuses (+$bonus pts) pushed them to the top of the table.';
    }
    return 'The highest squad score from the draft — chemistry and line '
        'leaders made the difference.';
  }

  @override
  Widget build(BuildContext context) {
    final winners = _winners;
    final isShared = winners.length > 1;
    final isForfeit = game.result?.reason == 'forfeit';
    final iAmWinner =
        localPlayerId != null &&
        winners.any((w) => w.playerId == localPlayerId);

    if (winners.isEmpty) {
      return const SizedBox.shrink();
    }

    final names = winners.map(_displayName).join(' & ');
    final reason = _winReason(winners.first);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(HESpacing.xl),
          decoration: BoxDecoration(
            // The victory stage: a deep plum ground with the gold worked in
            // as a diagonal shaft of light rather than an even wash, so the
            // composition has a direction and the trophy sits at the bright
            // end of it.
            // Gold as a *glow behind the trophy*, not a wash across the whole
            // stage. A flat 18% gold band stretched over a 1900px hero turned
            // muddy brown — the colour only reads as gold when it stays
            // concentrated and the surface around it stays deep plum.
            gradient: iAmWinner
                ? RadialGradient(
                    center: const Alignment(0, -0.55),
                    radius: 0.95,
                    colors: [
                      HETheme.pfGold.withValues(alpha: 0.20),
                      HETheme.pfGold.withValues(alpha: 0.06),
                      HETheme.pfSurfaceDeep,
                    ],
                    stops: const [0.0, 0.38, 1.0],
                  )
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      HETheme.pfSurfaceRaised,
                      HETheme.pfSurfaceGlass,
                    ],
                  ),
            borderRadius: HEShape.lg,
            border: Border.all(
              color: HETheme.pfGold.withValues(alpha: iAmWinner ? 0.55 : 0.25),
              width: iAmWinner ? 1.5 : 1,
            ),
            boxShadow: iAmWinner ? HEShadows.gold(intensity: 0.25) : null,
          ),
          // BUG FIX: a plain (non-Positioned) Stack child is placed at the
          // Stack's alignment, which defaults to topLeft — so the trophy
          // content was rendering left-aligned on a wide hero while the gold
          // radial behind it (a full-bleed background layer) stayed
          // mathematically centred on the whole box. The two drifted apart
          // on any screen wider than the content itself, which is exactly
          // "the cup isn't centred, there's a stray blob" on a 1900px hero.
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Asymmetric hex framing — a bracket at the top-left and
              // bottom-right only, never a full box. Decorative and
              // non-interactive; nothing here carries meaning on its own.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _VictoryStageFramePainter(
                      color: HETheme.pfGold.withValues(
                        alpha: iAmWinner ? 0.55 : 0.28,
                      ),
                    ),
                  ),
                ),
              ),
              Column(
            children: [
              // Trophy in a hex plate, so the trophy/rank/identity/score read
              // as one stacked hierarchy rather than four loose rows.
              ScaleTransition(
                scale: _trophyScale,
                child: Container(
                  padding: EdgeInsets.all(iAmWinner ? 14 : 10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: HETheme.pfGold.withValues(
                      alpha: iAmWinner ? 0.12 : 0.07,
                    ),
                    border: Border.all(
                      color: HETheme.pfGold.withValues(
                        alpha: iAmWinner ? 0.45 : 0.22,
                      ),
                    ),
                  ),
                  child: Icon(
                    Icons.emoji_events_rounded,
                    color: HETheme.pfGold,
                    size: iAmWinner ? 52 : 40,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FadeTransition(
                opacity: _contentFade,
                child: SlideTransition(
                  position: _contentSlide,
                  child: Column(
                    children: [
                      Text(
                        isShared
                            ? 'Joint Winners'
                            : (iAmWinner ? 'You Win!' : 'Winner'),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: HETheme.pfGold,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$names${isForfeit ? ' (by forfeit)' : ''}',
                        style: const TextStyle(
                          color: HETheme.pfTextPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (isShared) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: HETheme.pfGold.withValues(alpha: 0.15),
                            borderRadius: HEShape.pill,
                            border: Border.all(
                              color: HETheme.pfGold.withValues(alpha: 0.5),
                            ),
                          ),
                          child: const Text(
                            'SHARED RANK — EQUAL FINAL POINTS',
                            style: TextStyle(
                              color: HETheme.pfGold,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        reason,
                        style: const TextStyle(
                          color: HETheme.pfTextSecondary,
                          fontSize: 13,
                          height: 1.35,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (awards != null) ...[
                        const SizedBox(height: 16),
                        const Divider(color: HETheme.pfBorder, height: 1),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Flexible: two unbounded display names sharing
                            // one centered Row can exceed the available
                            // width on a narrow phone — neither chip
                            // previously had any way to shrink.
                            Flexible(
                              child: _heroChip(
                                '🏆',
                                'Champion',
                                awards!.champion.displayName,
                              ),
                            ),
                            const SizedBox(width: 20),
                            Flexible(
                              child: _heroChip(
                                '🥈',
                                'Runner-up',
                                awards!.runnerUp.displayName,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
              ),
            ],
          ),
        ),
        // Confetti only for the local player's own win — a burst on every
        // spectator's screen for someone else's result would just be noise.
        if (iAmWinner)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) =>
                    CustomPaint(painter: _ConfettiPainter(_controller.value)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _heroChip(String icon, String label, String value) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: HETheme.pfTextSecondary,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: HETheme.pfTextPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// The victory stage's asymmetric hex framing.
///
/// Two corner brackets — top-left and bottom-right only — with a chamfered
/// (hex-style) corner, rather than a symmetrical box. Static and purely
/// decorative: the win is stated in text, never by this frame.
class _VictoryStageFramePainter extends CustomPainter {
  const _VictoryStageFramePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = color;

    const inset = 2.0;
    // Clamped. Unbounded percentages drew a ~300px arm across a 1900px hero,
    // which read as a stray line rather than a corner bracket — the frame has
    // to stay a *corner* detail however wide the stage gets.
    final armX = (size.width * 0.16).clamp(28.0, 72.0);
    final armY = (size.height * 0.20).clamp(20.0, 56.0);
    const chamfer = 12.0;

    // Top-left bracket with a chamfered corner.
    canvas.drawPath(
      Path()
        ..moveTo(inset, inset + armY)
        ..lineTo(inset, inset + chamfer)
        ..lineTo(inset + chamfer, inset)
        ..lineTo(inset + armX, inset),
      paint,
    );

    // Bottom-right bracket, mirrored — the asymmetry comes from the two
    // arms being different lengths on each axis.
    final w = size.width - inset;
    final h = size.height - inset;
    canvas.drawPath(
      Path()
        ..moveTo(w, h - armY)
        ..lineTo(w, h - chamfer)
        ..lineTo(w - chamfer, h)
        ..lineTo(w - armX, h),
      paint,
    );
  }

  @override
  bool shouldRepaint(_VictoryStageFramePainter old) => old.color != color;
}

/// One-shot confetti burst for the local winner. Deterministic (seeded, not
/// `Random()` reseeded per frame) so the pieces trace fixed arcs instead of
/// jittering — same painter instance re-rendered as `progress` advances
/// 0→1 alongside the hero's entrance controller, then simply stops
/// repainting once the controller completes.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.progress);

  final double progress;

  static const _count = 26;
  static const _colors = [
    HETheme.pfGold,
    Color(0xFFFFFFFF),
    HETheme.pfAccentViolet,
    HETheme.pfSuccess,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final rnd = math.Random(7); // fixed seed — a stable, repeatable burst
    for (var i = 0; i < _count; i++) {
      final angle = rnd.nextDouble() * math.pi - math.pi / 2 - math.pi / 4;
      final speed = 0.55 + rnd.nextDouble() * 0.45;
      final startX = size.width * (0.3 + rnd.nextDouble() * 0.4);
      final delay = rnd.nextDouble() * 0.25;
      final t = ((progress - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;

      // Ballistic-looking arc: fast outward burst, gravity pulls it down,
      // fading out over the back half so it doesn't just vanish mid-air.
      final dx = math.cos(angle) * speed * 90 * t;
      final dy = math.sin(angle) * speed * 60 * t + 260 * t * t;
      final opacity = (1 - t).clamp(0.0, 1.0) * (t < 0.15 ? t / 0.15 : 1.0);
      if (opacity <= 0) continue;

      final paint = Paint()
        ..color = _colors[i % _colors.length].withValues(alpha: opacity);
      canvas.save();
      canvas.translate(startX + dx, size.height * 0.15 + dy);
      canvas.rotate(t * math.pi * 3 * (i.isEven ? 1 : -1));
      canvas.drawRect(const Rect.fromLTWH(-3, -5, 6, 10), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}
