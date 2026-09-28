import 'package:flutter/material.dart';
import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/app/theme.dart' show HERadius;
import 'package:hidden_eleven/features/tournament/models/tournament_models.dart';
import 'package:hidden_eleven/shared/widgets/help_dialog.dart';

/// The tournament's stat-leader summary for the result page — Top Scorer,
/// Top Assists, Top Contributions, Best Rating, and Clean Sheets — with every
/// genuinely shared award shown as such (all tied winners, a SHARED badge,
/// and their actual per-winner points), never collapsed into a fake single
/// winner. Champion/Runner-up are deliberately NOT repeated here — they
/// already own the result page's hero section (see ResultHeroSummary), and
/// showing them again in this grid would just dilute both.
class TournamentAwardsSummary extends StatelessWidget {
  final TournamentAwardsModel awards;

  const TournamentAwardsSummary({super.key, required this.awards});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceRaised,
        borderRadius: BorderRadius.circular(HERadius.lg),
        border: Border.all(color: HETheme.pfBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'TOURNAMENT AWARDS',
            style: TextStyle(
              color: HETheme.pfTextSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Ties are resolved by fewer minutes played; if still tied, the '
            'award is shared and points are split equally, rounded up.',
            style: TextStyle(
              color: HETheme.pfTextMuted,
              fontSize: 10.5,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _AwardTile(
                icon: '⚽',
                title: 'Top Scorer',
                names: awards.topScorer.map((e) => e.playerName).toList(),
                detail: awards.topScorer.isEmpty
                    ? null
                    : '${awards.topScorer.first.goals} goals',
                aiBlocked: awards.blockedCategories.contains('Top Scorer'),
              ),
              _AwardTile(
                icon: '🎯',
                title: 'Top Assists',
                names: awards.mostAssists.map((e) => e.playerName).toList(),
                detail: awards.mostAssists.isEmpty
                    ? null
                    : '${awards.mostAssists.first.assists} assists',
                aiBlocked: awards.blockedCategories.contains('Most Assists'),
              ),
              _AwardTile(
                icon: '🔥',
                title: 'Top Contributions',
                helpText: 'Goals + assists combined.',
                names: awards.topContributions
                    .map((e) => e.playerName)
                    .toList(),
                detail: awards.topContributions.isEmpty
                    ? null
                    : '${awards.topContributions.first.contributions} (G+A)'
                          '${awards.topContributions.first.minutesPlayed > 0 ? " · ${awards.topContributions.first.minutesPlayed}'" : ''}',
              ),
              _AwardTile(
                icon: '⭐',
                title: 'Best Rating',
                names: awards.highestAvgRating
                    .map((e) => e.playerName)
                    .toList(),
                detail: awards.highestAvgRating.isEmpty
                    ? null
                    : awards.highestAvgRating.first.avgRating.toStringAsFixed(
                        2,
                      ),
                aiBlocked: awards.blockedCategories.contains('Best Rating'),
              ),
              if (awards.cleanSheets.isNotEmpty)
                _AwardTile(
                  icon: '🧤',
                  title: 'Clean Sheets',
                  names: awards.cleanSheets.map((e) => e.playerName).toList(),
                  detail: '${awards.cleanSheets.first.cleanSheets}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AwardTile extends StatelessWidget {
  final String icon;
  final String title;
  final List<String> names;
  final String? detail;
  final String? helpText;

  /// True when an AI participant was among the leaders for this category,
  /// so no human received its bonus points — shown as a subtle, informative
  /// note rather than an alarming color, since the leaderboard result itself
  /// (`names`) is still accurate and worth celebrating.
  final bool aiBlocked;

  const _AwardTile({
    required this.icon,
    required this.title,
    required this.names,
    this.detail,
    this.helpText,
    this.aiBlocked = false,
  });

  @override
  Widget build(BuildContext context) {
    final isShared = names.length > 1;
    final hasWinner = names.isNotEmpty;

    return Container(
      width: 156,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: HETheme.pfSurfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HETheme.pfBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    color: HETheme.pfTextSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              if (helpText != null) InlineHelp(helpText!, size: 11),
              if (isShared) ...[
                const SizedBox(width: 3),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: HETheme.pfGold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text(
                    'SHARED',
                    style: TextStyle(
                      color: HETheme.pfGold,
                      fontSize: 7,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          if (!hasWinner)
            const Text(
              '—',
              style: TextStyle(color: HETheme.pfTextMuted, fontSize: 12),
            )
          else ...[
            Text(
              names.join(' & '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: HETheme.pfTextPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (detail != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  detail!,
                  style: const TextStyle(
                    color: HETheme.pfTextSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
            if (aiBlocked)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '🤖 AI led — no bonus awarded',
                  style: TextStyle(
                    color: HETheme.pfSecondaryViolet,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
