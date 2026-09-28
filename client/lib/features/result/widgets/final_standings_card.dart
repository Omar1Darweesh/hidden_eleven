import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_motion.dart';
import 'package:hidden_eleven/app/he_shape.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';
import 'package:hidden_eleven/features/tournament/models/tournament_models.dart';
import 'package:hidden_eleven/shared/widgets/he_card.dart';
import 'package:hidden_eleven/shared/widgets/rank_medallion.dart';

/// The final ranking, redesigned to answer "how many points, and why" at a
/// glance: rank (shared-aware), name, award badges, and total points. Tapping
/// a row selects that user for the points-breakdown / squad sections below
/// (same selection contract as the screen already used).
class FinalStandingsCard extends StatefulWidget {
  final GameState game;
  final List<String> orderedIds;
  final String? localPlayerId;
  final Map<String, PlayerResult> rankMap;
  final TournamentAwardsModel? awards;
  final String? selectedPlayerId;
  final ValueChanged<int> onTap;

  const FinalStandingsCard({
    super.key,
    required this.game,
    required this.orderedIds,
    required this.localPlayerId,
    required this.rankMap,
    required this.selectedPlayerId,
    required this.onTap,
    this.awards,
  });

  @override
  State<FinalStandingsCard> createState() => _FinalStandingsCardState();
}

class _FinalStandingsCardState extends State<FinalStandingsCard>
    with SingleTickerProviderStateMixin {
  /// R3's stagger. Null under reduced motion — never constructed.
  AnimationController? _stagger;
  bool _staggerPlayed = false;

  GameState get game => widget.game;
  List<String> get orderedIds => widget.orderedIds;
  String? get localPlayerId => widget.localPlayerId;
  Map<String, PlayerResult> get rankMap => widget.rankMap;
  TournamentAwardsModel? get awards => widget.awards;
  String? get selectedPlayerId => widget.selectedPlayerId;
  ValueChanged<int> get onTap => widget.onTap;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Runs once. Selecting a row, a provider update, a tab switch or a
    // navigation return rebuilds this card — none of them restage it.
    if (_staggerPlayed) return;
    _staggerPlayed = true;
    if (HEMotion.reduced(context)) return;
    _stagger = AnimationController(vsync: this, duration: HEMotion.entrance)
      ..forward();
  }

  @override
  void dispose() {
    _stagger?.dispose();
    super.dispose();
  }

  /// Position in the reveal sequence: champion, then the local player, then
  /// the rest in finishing order.
  int _revealOrder({
    required int index,
    required String playerId,
    required int? rank,
  }) {
    if (rank == 1) return 0;
    if (playerId == localPlayerId) return 1;
    return index + 2;
  }

  List<String> _badgesFor(String participantId) {
    final a = awards;
    if (a == null) return const [];
    final badges = <String>[];
    if (participantId == a.champion.participantId) badges.add('🏆');
    if (participantId == a.runnerUp.participantId) badges.add('🥈');
    if (a.topScorer.any((e) => e.participantId == participantId)) {
      badges.add('⚽');
    }
    if (a.mostAssists.any((e) => e.participantId == participantId)) {
      badges.add('🎯');
    }
    if (a.topContributions.any((e) => e.participantId == participantId)) {
      badges.add('🔥');
    }
    if (a.highestAvgRating.any((e) => e.participantId == participantId)) {
      badges.add('⭐');
    }
    if (a.cleanSheets.any((e) => e.participantId == participantId)) {
      badges.add('🧤');
    }
    return badges;
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...orderedIds]
      ..sort((a, b) {
        final ra = rankMap[a]?.rank ?? 99;
        final rb = rankMap[b]?.rank ?? 99;
        return ra.compareTo(rb);
      });

    final rankCounts = <int, int>{};
    for (final id in sorted) {
      final r = rankMap[id]?.rank ?? 99;
      rankCounts[r] = (rankCounts[r] ?? 0) + 1;
    }

    return HECard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Text(
                  'FINAL STANDINGS',
                  style: TextStyle(
                    color: HETheme.pfTextSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
          ),
          for (int i = 0; i < sorted.length; i++) ...[
            _StaggeredRow(
              controller: _stagger,
              // R3's reading order: the champion first, then your own row,
              // then everyone else in finishing order.
              order: _revealOrder(
                index: i,
                playerId: sorted[i],
                rank: rankMap[sorted[i]]?.rank,
              ),
              total: sorted.length,
              child: _StandingsRow(
                playerId: sorted[i],
                game: game,
                isLocal: sorted[i] == localPlayerId,
                isSelected: sorted[i] == selectedPlayerId,
                result: rankMap[sorted[i]],
                isSharedRank:
                    (rankCounts[rankMap[sorted[i]]?.rank ?? 99] ?? 1) > 1,
                badges: _badgesFor(sorted[i]),
                // Base/bonus breakdown is only ever shown for a tournament
                // game (see _StandingsRow's own doc comment) — null here
                // means "no tournament happened", not just "no data yet".
                hasTournamentAwards: awards != null,
                onTap: () => onTap(orderedIds.indexOf(sorted[i])),
              ),
            ),
            if (i < sorted.length - 1)
              const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        ],
      ),
    );
  }
}

// Below this row width, there isn't room for a Base/Bonus mini-column beside
// the existing Total badge without crowding the name — the compact subtext
// variant is used instead. This is a per-row width, not the screen's own
// wide/narrow breakpoint: the wide _WideLayout's standings column is a fixed
// 320px SizedBox, actually NARROWER than a typical mobile card, so branching
// on screen size here would pick the wrong variant on desktop.
const double _kBesideVariantMinWidth = 340.0;

class _StandingsRow extends StatelessWidget {
  final String playerId;
  final GameState game;
  final bool isLocal;
  final bool isSelected;
  final PlayerResult? result;
  final bool isSharedRank;
  final List<String> badges;

  /// True only for a tournament game (see FinalStandingsCard's own doc
  /// comment) — gates whether Base/Bonus is shown at all. Outside a
  /// tournament, base score IS the total (bonus is always 0), so showing a
  /// split would just repeat the existing Total badge as noise.
  final bool hasTournamentAwards;

  final VoidCallback onTap;

  const _StandingsRow({
    required this.playerId,
    required this.game,
    required this.isLocal,
    required this.isSelected,
    required this.result,
    required this.isSharedRank,
    required this.badges,
    required this.hasTournamentAwards,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final player = game.players.where((p) => p.id == playerId).firstOrNull;
    final rank = result?.rank ?? 0;
    final score = result?.score ?? 0;
    final name = player?.displayName ?? result?.displayName ?? '—';

    // Same base/total computation PointsBreakdownCard already uses (see its
    // own build method) — bonus is derived by subtraction rather than
    // re-summing award categories, so Base + Bonus == Total always, by
    // construction, with no risk of drifting from PointsBreakdownCard's own
    // displayed number.
    final breakdown = result?.scoreBreakdown;
    final total = result?.score ?? breakdown?.finalScore.round() ?? 0;
    final baseScore = breakdown?.finalScore.round() ?? total;
    final bonus = total - baseScore;
    final bonusText = bonus >= 0 ? '+$bonus' : '$bonus';
    final showBaseBonus = hasTournamentAwards && breakdown != null;
    final isChampion = rank == 1;

    // Champion gets a restrained gold-tinted resting background — separate
    // from (and overridden by, when both apply) the violet tap-to-select
    // highlight, so "this is the champion row" reads at a glance without
    // requiring a tap. The current-player accent below is a distinct signal
    // again: a persistent left edge bar, not tied to selection at all, so
    // "which row is me" never disappears just because a different row is
    // selected for the breakdown view.
    final restingColor = isSelected
        ? HETheme.pfAccentViolet.withValues(alpha: 0.08)
        : isChampion
        ? HETheme.pfGold.withValues(alpha: 0.06)
        : Colors.transparent;

    return ClipRRect(
      borderRadius: HEShape.md,
      child: Stack(
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: HEShape.md,
            child: AnimatedContainer(
              duration: HEMotion.reduced(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              padding: EdgeInsets.fromLTRB(
                isLocal ? 20 : 16,
                14,
                16,
                14,
              ),
              decoration: BoxDecoration(
                color: restingColor,
                borderRadius: HEShape.md,
              ),
              child: LayoutBuilder(
          builder: (context, constraints) {
            final showBeside =
                showBaseBonus &&
                constraints.maxWidth >= _kBesideVariantMinWidth;
            final showSubtext = showBaseBonus && !showBeside;
            return Row(
              children: [
                // Rank medallion — one hexagon shape across every tier,
                // gold/silver/bronze/violet-neutral fill, always numeral.
                RankMedallion(rank: rank),
                const SizedBox(width: 10),

                HEAvatar(name: name, size: 34),
                const SizedBox(width: 12),

                // Name + shared-rank / award badges
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              isLocal ? '$name (you)' : name,
                              style: TextStyle(
                                color: isSelected
                                    ? HETheme.pfAccentViolet
                                    : HETheme.pfTextPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isSharedRank) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: HETheme.pfGold.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: const Text(
                                'TIED',
                                style: TextStyle(
                                  color: HETheme.pfGold,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (badges.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            badges.join(' '),
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      // Compact mobile-friendly variant: Base/Bonus as a subtext
                      // line under the name instead of extra horizontal columns
                      // (see showBeside/showSubtext above).
                      if (showSubtext)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Base $baseScore · Bonus $bonusText',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: HETheme.pfTextMuted,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Yellow-card penalty chip
                if ((game.yellowPenalties[playerId] ?? 0) > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: HETheme.pfWarning.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: HETheme.pfWarning.withValues(alpha: 0.7),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.style_rounded,
                          color: HETheme.pfWarning,
                          size: 11,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '−${game.yellowPenalties[playerId]}',
                          style: TextStyle(
                            color: HETheme.pfWarning,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                // Base/Bonus, beside the Total badge — wide-row variant only
                // (showSubtext handles the same data at narrow widths, above).
                // Deliberately plain text, no chip/border — the Total badge
                // below stays the visually dominant element; this is a quiet
                // explanation beside it, not a competing badge.
                if (showBeside) ...[
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Base $baseScore',
                        style: const TextStyle(
                          color: HETheme.pfTextMuted,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Bonus $bonusText',
                        style: const TextStyle(
                          color: HETheme.pfTextSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                ],

                // Score badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: rank == 1
                        ? HETheme.pfGold.withValues(alpha: 0.12)
                        : HETheme.pfSurfaceRaised,
                    borderRadius: BorderRadius.circular(HETheme.radiusSm),
                    border: Border.all(
                      color: rank == 1
                          ? HETheme.pfGold.withValues(alpha: 0.40)
                          : HETheme.pfBorder,
                    ),
                  ),
                  // Fixed width + tabular figures so the scores form a clean
                  // right-aligned column instead of jittering with digit
                  // width — the main thing that made these rows read as an
                  // undifferentiated stack.
                  child: SizedBox(
                    width: 34,
                    child: Text(
                      '$score',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: rank == 1
                            ? HETheme.pfGold
                            : HETheme.pfTextPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ],
            );
                },
              ),
            ),
          ),
          // Current-player accent — a persistent left edge bar, independent
          // of tap-selection, so "which row is me" is never lost when a
          // different row happens to be selected for the breakdown view.
          if (isLocal)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 3,
              child: Container(color: HETheme.pfAccentViolet),
            ),
        ],
      ),
    );
  }
}

/// R3: fades and lifts one standings row into place as part of the card's
/// single staggered entrance.
///
/// With a null [controller] (reduced motion, or after the stagger finished)
/// the row is returned untouched at its final state — no wrapper, no opacity,
/// nothing hidden or delayed. Rows stay tappable throughout either way, since
/// neither `FadeTransition` nor `SlideTransition` absorbs hit tests.
class _StaggeredRow extends StatelessWidget {
  const _StaggeredRow({
    required this.controller,
    required this.order,
    required this.total,
    required this.child,
  });

  final AnimationController? controller;
  final int order;
  final int total;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null) return child;

    // Every row finishes within the one `entrance` window; later rows simply
    // start later inside it, so the whole list never outlasts a single token.
    final span = total <= 1 ? 1.0 : 1.0 / (total + 1);
    final begin = (order * span).clamp(0.0, 0.6);
    final animation = CurvedAnimation(
      parent: c,
      curve: Interval(begin, 1.0, curve: HEMotion.easeOut),
    );

    return RepaintBoundary(
      child: FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.12),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
    );
  }
}
