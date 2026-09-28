import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hidden_eleven/app/he_motion.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/shared/widgets/event_atmosphere_background.dart';
import 'package:hidden_eleven/shared/widgets/rank_medallion.dart';
import '../models/tournament_models.dart';
import '../providers/tournament_provider.dart';

class TournamentCompleteScreen extends ConsumerStatefulWidget {
  const TournamentCompleteScreen({super.key});

  @override
  ConsumerState<TournamentCompleteScreen> createState() =>
      _TournamentCompleteScreenState();
}

class _TournamentCompleteScreenState
    extends ConsumerState<TournamentCompleteScreen>
    with TickerProviderStateMixin {
  late final AnimationController _trophyController;

  /// T6: the champion celebration burst. One shot, built only when motion is
  /// allowed, and the only new controller on this screen — the trophy's own
  /// existing pop is unchanged.
  AnimationController? _burst;

  bool _showChampion = false;
  bool _showAwards = false;

  @override
  void initState() {
    super.initState();
    _trophyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _trophyController.addStatusListener((status) {
      // Reduced motion sets `_showChampion`/`_showAwards` directly (below)
      // and jumps the controller straight to its end value — which itself
      // fires this listener (a value assignment that crosses into
      // `completed` still notifies status listeners, it's only *building*
      // one that reduced motion skips). Without this guard the two
      // Future.delayed reveals below would still schedule and fire, leaving
      // real pending timers behind purely for a redundant, already-applied
      // state change.
      if (status == AnimationStatus.completed && !HEMotion.reduced(context)) {
        // T6: the burst rides the trophy landing — one contained particle
        // moment, not a loop, and nothing waits on it.
        _burst ??= AnimationController(vsync: this, duration: HEMotion.waiting)
          ..forward();
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) setState(() => _showChampion = true);
        });
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) setState(() => _showAwards = true);
        });
      }
    });

    // Start the trophy animation after the first frame — unless the OS asks
    // for reduced motion, in which case every layer jumps straight to its
    // settled state (trophy landed, champion + awards already shown) rather
    // than animating in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (HEMotion.reduced(context)) {
        setState(() {
          _trophyController.value = 1.0;
          _showChampion = true;
          _showAwards = true;
        });
      } else {
        _trophyController.forward();
      }
    });
  }

  @override
  void dispose() {
    _trophyController.dispose();
    _burst?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final awards = ref.watch(tournamentCompleteProvider);

    if (awards == null) {
      return const Scaffold(
        backgroundColor: HETheme.pfBgVoid,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final myId = ref.watch(myParticipantIdProvider);
    final reduceMotion = HEMotion.reduced(context);

    return Scaffold(
      backgroundColor: HETheme.pfBgVoid,
      body: Stack(
        children: [
          // The champion moment is exactly what the reserved gold atmosphere
          // exists for — lit here, centred behind the trophy.
          const Positioned.fill(
            child: EventAtmosphereBackground(
              variant: EventAtmosphereVariant.results,
              goldFocus: true,
              goldAlignment: Alignment(0, -0.55),
            ),
          ),
          SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                const SizedBox(height: 64),
                // Trophy — elastic scale-in.
                ScaleTransition(
                  scale: CurvedAnimation(
                    parent: _trophyController,
                    curve: Curves.elasticOut,
                  ),
                  child: SizedBox(
                    width: 200,
                    height: 140,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // T6: a contained burst behind the trophy — bounded to
                        // this box rather than the whole screen, decorative
                        // only, and never covering the champion name or the
                        // navigation below.
                        if (_burst != null)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: RepaintBoundary(
                                child: AnimatedBuilder(
                                  animation: _burst!,
                                  builder: (context, _) => CustomPaint(
                                    painter: _ChampionBurstPainter(
                                      _burst!.value,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const Icon(
                          Icons.emoji_events,
                          size: 96,
                          color: HETheme.pfGold,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                // Champion — fades in after the trophy lands.
                AnimatedOpacity(
                  opacity: _showChampion ? 1.0 : 0.0,
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 400),
                  child: Column(
                    children: [
                      Text(
                        'TOURNAMENT CHAMPION',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: HETheme.pfTextSecondary,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '✨ ${awards.champion.displayName} ✨',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: HETheme.pfTextPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const RankMedallion(rank: 1, size: 32),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Runner-up: ',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: HETheme.pfTextSecondary),
                          ),
                          // Flexible: mainAxisAlignment.center doesn't shrink
                          // anything, and a club/player display name is
                          // unbounded — this is the element that grows.
                          Flexible(
                            child: Text(
                              awards.runnerUp.displayName,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: HETheme.pfTextPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const RankMedallion(rank: 2, size: 20),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Awards — slide up + fade in.
                AnimatedSlide(
                  offset: _showAwards ? Offset.zero : const Offset(0, 0.15),
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  child: AnimatedOpacity(
                    opacity: _showAwards ? 1.0 : 0.0,
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 300),
                    child: _buildAwardsSection(awards),
                  ),
                ),
                const SizedBox(height: 32),
                // Points — same reveal timing as awards.
                AnimatedSlide(
                  offset: _showAwards ? Offset.zero : const Offset(0, 0.15),
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  child: AnimatedOpacity(
                    opacity: _showAwards ? 1.0 : 0.0,
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 300),
                    child: _buildPointsSection(awards, myId),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
          ),
        ],
      ),
    );
  }

  Widget _buildAwardsSection(TournamentAwardsModel awards) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceRaised,
        borderRadius: HEShape.sm,
        border: Border.all(color: HETheme.pfBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _awardRow(
            '⚽',
            'Top Scorer',
            awards.topScorerName,
            awards.topScorerGoals != null
                ? '${awards.topScorerGoals} goals'
                : null,
          ),
          _awardRow(
            '🎯',
            'Most Assists',
            awards.mostAssistsName,
            awards.mostAssistsCount != null
                ? '${awards.mostAssistsCount} assists'
                : null,
          ),
          _awardRow(
            '⭐',
            'Best Player',
            awards.highestRatingName,
            awards.highestRatingValue?.toStringAsFixed(1),
          ),
        ],
      ),
    );
  }

  Widget _awardRow(String icon, String label, String? name, String? detail) {
    if (name == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: HETheme.pfTextSecondary,
                    fontSize: 11,
                  ),
                ),
                Text(
                  name,
                  style: const TextStyle(
                    color: HETheme.pfTextPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          if (detail != null)
            Text(
              detail,
              style: const TextStyle(color: HETheme.pfGold, fontSize: 13),
            ),
        ],
      ),
    );
  }

  Widget _buildPointsSection(TournamentAwardsModel awards, String? myId) {
    final entries = <Widget>[];

    final champId = awards.champion.participantId;
    final champPts = awards.pointsAwarded[champId] ?? 0;
    if (champPts > 0) {
      entries.add(
        _pointRow(awards.champion.displayName, champPts, isMe: champId == myId),
      );
    }

    final runnerUpId = awards.runnerUp.participantId;
    final runnerUpPts = awards.pointsAwarded[runnerUpId] ?? 0;
    if (runnerUpPts > 0) {
      entries.add(
        _pointRow(
          awards.runnerUp.displayName,
          runnerUpPts,
          isMe: runnerUpId == myId,
        ),
      );
    }

    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceRaised,
        borderRadius: HEShape.sm,
        border: Border.all(color: HETheme.pfBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'POINTS AWARDED',
            style: TextStyle(
              color: HETheme.pfTextSecondary,
              fontSize: 11,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          ...entries,
        ],
      ),
    );
  }

  Widget _pointRow(String name, int points, {required bool isMe}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              isMe ? '$name (you)' : name,
              style: TextStyle(
                color: isMe ? HETheme.pfSuccess : HETheme.pfTextPrimary,
                fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ),
          Text(
            '+$points pts',
            style: TextStyle(
              color: isMe ? HETheme.pfSuccess : HETheme.pfGold,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

/// T6: the champion burst — a small ring of gold particles thrown outward
/// from the trophy once, then faded.
///
/// Deterministic (fixed seed, no randomness per frame) so it renders the same
/// way every time and can be reasoned about in a test. Bounded to the trophy's
/// own box and drawn under an [IgnorePointer], so it never covers or blocks
/// the champion name, the awards, or any navigation.
class _ChampionBurstPainter extends CustomPainter {
  const _ChampionBurstPainter(this.progress);

  /// 0 → 1 across the burst's single run.
  final double progress;

  static const int _count = 18;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final t = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    // Fade out over the back half, so the burst resolves rather than vanishes.
    final fade = progress < 0.5 ? 1.0 : 1.0 - ((progress - 0.5) * 2);
    final paint = Paint();

    for (var i = 0; i < _count; i++) {
      final angle = (i / _count) * 2 * math.pi;
      // Alternating reach keeps the ring from reading as a perfect circle.
      final reach = (i.isEven ? 0.86 : 0.62) * size.shortestSide * 0.62;
      final d = reach * t;
      final offset = Offset(
        center.dx + math.cos(angle) * d,
        center.dy + math.sin(angle) * d,
      );
      paint.color = (i % 3 == 0 ? HETheme.pfAccentVioletGlow : HETheme.pfGold)
          .withValues(alpha: 0.75 * fade);
      canvas.drawCircle(offset, 2.6 * (1 - t * 0.45), paint);
    }
  }

  @override
  bool shouldRepaint(_ChampionBurstPainter old) => old.progress != progress;
}
