import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_motion.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/shared/widgets/count_up_text.dart';
import 'package:hidden_eleven/shared/widgets/rank_medallion.dart';

/// The viewer's own finish, promoted to its own card so it reads as a
/// dedicated answer to "where did I stand" rather than a bar tucked inside
/// the winner hero. Always shown when the local player has a result,
/// regardless of whether they won.
///
/// Extracted from `ResultHeroSummary`'s private `_YourResultBar` — same
/// visual language (medallion, rank, score, violet card, "YOUR RESULT"
/// label so the current-player emphasis is never carried by color alone) —
/// plus one net-new element: a friendly one-line summary sentence built
/// purely from data already on [PlayerResult] and the optional [leaderScore]
/// (the tournament/game's top score, if known) — no invented analytics.
class YourResultCard extends StatefulWidget {
  const YourResultCard({
    super.key,
    required this.result,
    required this.isWinner,
    this.leaderScore,
  });

  final PlayerResult result;
  final bool isWinner;

  /// The highest score in the standings, when known — used only to phrase
  /// "N points behind the leader" in the summary line. Omit (or pass null)
  /// when unavailable; the sentence simply drops that clause.
  final int? leaderScore;

  @override
  State<YourResultCard> createState() => _YourResultCardState();
}

class _YourResultCardState extends State<YourResultCard>
    with SingleTickerProviderStateMixin {
  /// R2's medallion settle. Null under reduced motion — never constructed,
  /// never merely paused.
  AnimationController? _settle;

  /// Guards against replay: the settle runs once for the life of this card,
  /// so a `game_state` broadcast, provider update, tab switch, orientation
  /// change or navigation return re-renders at the settled state.
  bool _settlePlayed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settlePlayed) return;
    _settlePlayed = true;
    if (HEMotion.reduced(context)) return;
    _settle = AnimationController(vsync: this, duration: HEMotion.land)
      ..forward();
  }

  @override
  void dispose() {
    _settle?.dispose();
    super.dispose();
  }

  PlayerResult get result => widget.result;
  bool get isWinner => widget.isWinner;
  int? get leaderScore => widget.leaderScore;

  int get _score => result.score ?? result.scoreBreakdown?.finalScore.round() ?? 0;

  String get _summary {
    final ord = _ordinal(result.rank);
    if (isWinner) {
      return "You finished $ord with $_score points — the top score on the table.";
    }
    final gap = leaderScore != null ? leaderScore! - _score : null;
    if (gap != null && gap > 0) {
      return 'You finished $ord with $_score points — $gap behind the leader.';
    }
    return 'You finished $ord with $_score points.';
  }

  static String _ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    switch (n % 10) {
      case 1:
        return '${n}st';
      case 2:
        return '${n}nd';
      case 3:
        return '${n}rd';
      default:
        return '${n}th';
    }
  }

  @override
  Widget build(BuildContext context) {
    // When the viewer IS the winner, the top row repeats the hero's own
    // headline, so it stays compact and quiet rather than competing with the
    // gold "You Win!" treatment. Otherwise it's the primary "where do I
    // stand" answer and gets the stronger violet card treatment.
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 14, 16, 14),
      decoration: BoxDecoration(
        // Layered violet — identity colour, deliberately distinct from the
        // gold reserved for the champion and from the flat rows of the
        // standings list below.
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            HETheme.pfAccentViolet.withValues(alpha: isWinner ? 0.14 : 0.18),
            HETheme.pfSurfaceRaised,
          ],
          stops: const [0.0, 0.85],
        ),
        borderRadius: HEShape.lg,
        border: Border.all(
          color: HETheme.pfAccentViolet.withValues(
            alpha: isWinner ? 0.35 : 0.5,
          ),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: HETheme.pfAccentViolet.withValues(alpha: 0.14),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Persistent violet edge — the same "this row is you" device the
          // standings list uses, so the two read as one idea.
          Container(
            width: 4,
            height: 62,
            decoration: BoxDecoration(
              color: HETheme.pfAccentViolet,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
          // The medallion leads: placement is the headline of a personal
          // result, and RankMedallion stays the single rank language.
          //
          // R2's settle scales it into place once. The medallion is fully
          // rendered throughout — the scale never hides the rank.
          _SettlingMedallion(rank: result.rank, settle: _settle),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Flexible(
                      child: Text(
                        'YOUR RESULT',
                        style: TextStyle(
                          color: HETheme.pfTextSecondary,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '#${result.rank}',
                      style: const TextStyle(
                        color: HETheme.pfTextPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // The score is the number the player came for — largest
                // element in the card after the medallion.
                //
                // R2: counts up once on mount. Nothing waits on it — Back to
                // Home and every other control are live from the first frame,
                // and under reduced motion the final number is all that is
                // ever painted.
                CountUpText(
                  value: _score,
                  suffix: ' pts',
                  style: const TextStyle(
                    color: HETheme.pfAccentVioletGlow,
                    fontSize: 24,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _summary,
                  style: const TextStyle(
                    color: HETheme.pfTextSecondary,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The rank medallion, scaled into place once by R2's settle.
///
/// Kept separate so the medallion's own rendering is untouched: this only
/// wraps it. With a null [settle] (reduced motion, or after the animation has
/// finished) it renders at full size with no transform at all.
class _SettlingMedallion extends StatelessWidget {
  const _SettlingMedallion({required this.rank, required this.settle});

  final int rank;
  final AnimationController? settle;

  @override
  Widget build(BuildContext context) {
    final medallion = RankMedallion(rank: rank, size: 46);
    final controller = settle;
    if (controller == null) return medallion;

    return RepaintBoundary(
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.82, end: 1.0).animate(
          CurvedAnimation(parent: controller, curve: HEMotion.overshoot),
        ),
        child: medallion,
      ),
    );
  }
}
