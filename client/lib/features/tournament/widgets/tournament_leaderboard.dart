import 'package:flutter/material.dart';

import 'package:hidden_eleven/app/he_theme.dart';
import 'package:hidden_eleven/shared/widgets/help_dialog.dart';
import '../models/tournament_models.dart';
import 'fixture_capsule.dart';

/// Live tournament leaderboard: top scorers, assists, contributions, ratings,
/// clean sheets, and the points table. Stateless and derived purely from the
/// shared providers, so every player sees identical numbers and there is
/// nothing to leak or dispose.
///
/// Before the tournament ends, the stat panels show a live, client-computed
/// approximation ("so far"). Once `awards` arrives (tournament complete), the
/// scorer/assist/contribution/rating panels switch to the server's
/// authoritative, tie-broken result — which may legitimately be a SHARED
/// award (see TournamentAwardsModel's tie-break documentation) rendered as
/// such, never collapsed into a single fake winner.
class TournamentLeaderboard extends StatelessWidget {
  final TournamentStateModel state;
  final Map<String, List<LiveMatchEvent>> liveEvents; // matchId → events
  final Map<String, TournamentMatchResult> results; // matchId → result
  final TournamentAwardsModel? awards;

  const TournamentLeaderboard({
    super.key,
    required this.state,
    required this.liveEvents,
    required this.results,
    this.awards,
  });

  /// All real participants (round 1 holds the full field).
  List<ParticipantSnapshot> get _realParticipants {
    if (state.rounds.isEmpty) return const [];
    final out = <ParticipantSnapshot>[];
    for (final m in state.rounds.first.matches) {
      for (final p in [m.participantA, m.participantB]) {
        if (p.kind == TournamentParticipantKind.real &&
            p.participantId.isNotEmpty) {
          out.add(p);
        }
      }
    }
    return out;
  }

  List<(String, String)> _topInt(Map<String, int> m, String Function(int) fmt) {
    final list = m.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list.take(3).map((e) => (e.key, fmt(e.value))).toList();
  }

  List<(String, String)> _topDouble(
    Map<String, double> m,
    String Function(double) fmt,
  ) {
    final list = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return list.take(3).map((e) => (e.key, fmt(e.value))).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isFinal = awards != null;
    final allEvents = liveEvents.values.expand((e) => e).toList();

    // Goals + assists across every match (live, "so far" approximation).
    final goals = <String, int>{};
    final assists = <String, int>{};
    for (final e in allEvents) {
      if (e.type == 'goal') {
        goals[e.playerName] = (goals[e.playerName] ?? 0) + 1;
        final a = e.assistPlayerName;
        if (a != null && a.isNotEmpty) assists[a] = (assists[a] ?? 0) + 1;
      }
    }
    final contributions = <String, int>{};
    for (final name in {...goals.keys, ...assists.keys}) {
      contributions[name] = (goals[name] ?? 0) + (assists[name] ?? 0);
    }

    // Best rating per player across completed matches.
    final ratings = <String, double>{};
    for (final r in results.values) {
      r.playerRatings.forEach((name, rating) {
        if (rating > (ratings[name] ?? 0)) ratings[name] = rating;
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('TOURNAMENT LEADERS'),
        const SizedBox(height: 6),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Ties are resolved by fewer minutes played; if still tied, the '
            'award is shared and points are split equally, rounded up.',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10.5,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            _StatPanel(
              icon: '⚽',
              title: 'Top Scorers',
              accent: HETheme.pfSuccess,
              entries: isFinal
                  ? awards!.topScorer
                        .map((e) => (e.playerName, '${e.goals}'))
                        .toList()
                  : _topInt(goals, (v) => '$v'),
              empty: isFinal ? 'No goals scored' : 'No goals yet',
              sharedAward: isFinal && awards!.topScorer.length > 1,
            ),
            _StatPanel(
              icon: '🎯',
              title: 'Top Assists',
              accent: HETheme.pfLavenderText,
              entries: isFinal
                  ? awards!.mostAssists
                        .map((e) => (e.playerName, '${e.assists}'))
                        .toList()
                  : _topInt(assists, (v) => '$v'),
              empty: isFinal ? 'No assists recorded' : 'No assists yet',
              sharedAward: isFinal && awards!.mostAssists.length > 1,
            ),
            _StatPanel(
              icon: '⭐',
              title: 'Top Ratings',
              accent: HETheme.pfGold,
              entries: isFinal
                  ? awards!.highestAvgRating
                        .map(
                          (e) => (e.playerName, e.avgRating.toStringAsFixed(2)),
                        )
                        .toList()
                  : _topDouble(ratings, (v) => v.toStringAsFixed(1)),
              empty: 'Awaiting results',
              sharedAward: isFinal && awards!.highestAvgRating.length > 1,
            ),
            _StatPanel(
              icon: '🧤',
              title: 'Clean Sheets',
              accent: HETheme.pfAccentVioletGlow,
              // Attributing a clean sheet to the real goalkeeper needs each
              // team's frozen lineup, which only the server-computed final
              // award carries — there's no honest live approximation, so the
              // panel simply waits for the final result rather than showing
              // a team/manager name in place of a player.
              entries: isFinal
                  ? awards!.cleanSheets
                        .map((e) => (e.playerName, '${e.cleanSheets}'))
                        .toList()
                  : const [],
              empty: isFinal ? 'None' : 'Awaiting results',
              sharedAward: isFinal && awards!.cleanSheets.length > 1,
            ),
            _ContributionsTable(
              isFinal: isFinal,
              sharedAward: isFinal && awards!.topContributions.length > 1,
              rows: isFinal
                  ? awards!.topContributions
                        .map(
                          (e) => (
                            name: e.playerName,
                            contributions: e.contributions,
                            goals: e.goals,
                            assists: e.assists,
                            minutes: e.minutesPlayed,
                          ),
                        )
                        .toList()
                  : (() {
                      final list =
                          contributions.entries
                              .where((e) => e.value > 0)
                              .toList()
                            ..sort((a, b) => b.value.compareTo(a.value));
                      return list
                          .take(3)
                          .map(
                            (e) => (
                              name: e.key,
                              contributions: e.value,
                              goals: goals[e.key] ?? 0,
                              assists: assists[e.key] ?? 0,
                              minutes: null as int?,
                            ),
                          )
                          .toList();
                    })(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildScoringLegend(),
        const SizedBox(height: 12),
        _buildPoints(),
      ],
    );
  }

  /// Makes the scoring system explicit: the point values behind every total,
  /// always visible (not just once the tournament ends). Before `awards`
  /// arrives (still mid-tournament) there is no server-echoed config yet, so
  /// this falls back to the same legacy defaults TournamentAwardsModel uses.
  Widget _buildScoringLegend() {
    final pointsConfig =
        awards?.pointsConfig ?? TournamentAwardsPointsConfig.legacyDefault;
    final entries = [
      ('Champion', pointsConfig.championPoints),
      ('Runner-up', pointsConfig.runnerUpPoints),
      ('Top Scorer', pointsConfig.topScorerBonus),
      ('Most Assists', pointsConfig.mostAssistsBonus),
      ('Best Rating', pointsConfig.highestRatingBonus),
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (label, pts) in entries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$label +$pts',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
      ],
    );
  }

  /// Per-participant category bonus lines for the points breakdown, e.g.
  /// "Top Scorer (shared) +8" — delegates to the model's single-source-of-
  /// truth `breakdownFor` (shared with the result page) rather than
  /// duplicating the shared-award logic here.
  List<String> _breakdownFor(ParticipantSnapshot p) {
    final a = awards;
    if (a == null) return const [];
    return a.breakdownFor(p.participantId).map((l) => l.display).toList();
  }

  Widget _buildPoints() {
    final isFinal = awards != null;
    final pts = awards?.pointsAwarded ?? const <String, int>{};
    final rows =
        _realParticipants.map((p) => (p, pts[p.participantId] ?? 0)).toList()
          ..sort((a, b) => b.$2.compareTo(a.$2));

    // The points table is championship-adjacent, so it keeps the standard
    // fixture surface — the two pure-statistic panels below use the quiet one.
    return FixtureCapsule(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(isFinal ? '🏆' : '📊', style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Text(
                isFinal ? 'FINAL POINTS' : 'LIVE POINTS',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              if (!isFinal)
                const Text(
                  'awarded at the final',
                  style: TextStyle(color: Colors.white24, fontSize: 10),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            const Text(
              'No players',
              style: TextStyle(color: Colors.white24, fontSize: 12),
            )
          else
            ...rows.map((r) {
              final breakdown = _breakdownFor(r.$1);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            r.$1.displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${r.$2} pts total',
                          style: TextStyle(
                            color: r.$2 > 0
                                ? HETheme.pfSuccess
                                : Colors.white24,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (breakdown.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          breakdown.join('  ·  '),
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _sectionHeader(String t) => Row(
    children: [
      const Expanded(child: Divider(color: Colors.white12)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          t,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 11,
            letterSpacing: 2,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      const Expanded(child: Divider(color: Colors.white12)),
    ],
  );
}

// ---------------------------------------------------------------------------
// _StatPanel — a small ranked leaderboard card. When `sharedAward` is true,
// every listed entry IS the (tied) winner — shown at rank 1 with a "SHARED"
// badge, never faked into a single winner.
// ---------------------------------------------------------------------------

class _StatPanel extends StatelessWidget {
  final String icon;
  final String title;
  final Color accent;
  final List<(String, String)> entries;
  final String empty;
  final bool sharedAward;

  const _StatPanel({
    required this.icon,
    required this.title,
    required this.accent,
    required this.entries,
    required this.empty,
    this.sharedAward = false,
  });

  @override
  Widget build(BuildContext context) {
    // A supporting statistic — deliberately the quiet surface so it never
    // competes with championship or final information.
    return SizedBox(
      width: 168,
      child: FixtureCapsule(
        emphasis: FixtureEmphasis.quiet,
        padding: const EdgeInsets.all(12),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              if (sharedAward)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'SHARED',
                    style: TextStyle(
                      color: accent,
                      fontSize: 7.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            Text(
              empty,
              style: const TextStyle(color: Colors.white24, fontSize: 11),
            )
          else
            ...entries.asMap().entries.map((e) {
              // A shared award means every entry here IS the joint winner —
              // all rank "1", not a fake sequential 1/2/3.
              final rank = sharedAward ? 1 : e.key + 1;
              final (name, value) = e.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Text(
                      '$rank',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      value,
                      style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ContributionsTable — the new "Top Contributions" card. A proper compact
// table (rank/name/contributions/goals/assists/minutes) rather than the
// simpler name+value row the other panels use, since it carries more columns
// — sits beside them in the same Wrap/visual system.
// ---------------------------------------------------------------------------

typedef _ContribRow = ({
  String name,
  int contributions,
  int goals,
  int assists,
  int? minutes,
});

class _ContributionsTable extends StatelessWidget {
  final List<_ContribRow> rows;
  final bool isFinal;
  final bool sharedAward;

  const _ContributionsTable({
    required this.rows,
    required this.isFinal,
    this.sharedAward = false,
  });

  static const _accent = HETheme.pfSecondaryViolet;

  @override
  Widget build(BuildContext context) {
    // Minutes only shown once real data exists (post-tournament) — during
    // live play minutes-played isn't tracked client-side, so the column
    // would just be a row of dashes; drop it entirely rather than clutter.
    final showMinutes = rows.any((r) => r.minutes != null);

    // Supporting statistic — quiet surface, same rationale as the panels above.
    return SizedBox(
      width: showMinutes ? 260 : 220,
      child: FixtureCapsule(
        emphasis: FixtureEmphasis.quiet,
        padding: const EdgeInsets.all(12),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('🔥', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'TOP CONTRIBUTIONS',
                  style: TextStyle(
                    color: _accent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const InlineHelp('Goals + assists combined.', size: 11),
              if (sharedAward)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'SHARED',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 7.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Text(
              isFinal ? 'No contributions' : 'No contributions yet',
              style: const TextStyle(color: Colors.white24, fontSize: 11),
            )
          else ...[
            _row(
              rank: '',
              name: 'PLAYER',
              contrib: 'C',
              goals: 'G',
              assists: 'A',
              minutes: showMinutes ? 'MIN' : null,
              headerStyle: true,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 3),
              child: Divider(color: Colors.white10, height: 1),
            ),
            ...rows.asMap().entries.map((e) {
              final rank = sharedAward ? 1 : e.key + 1;
              final r = e.value;
              return _row(
                rank: '$rank',
                name: r.name,
                contrib: '${r.contributions}',
                goals: '${r.goals}',
                assists: '${r.assists}',
                minutes: showMinutes ? '${r.minutes ?? '-'}' : null,
              );
            }),
          ],
        ],
        ),
      ),
    );
  }

  Widget _row({
    required String rank,
    required String name,
    required String contrib,
    required String goals,
    required String assists,
    String? minutes,
    bool headerStyle = false,
  }) {
    final labelStyle = TextStyle(
      color: headerStyle ? Colors.white38 : Colors.white,
      fontSize: headerStyle ? 8.5 : 12,
      fontWeight: headerStyle ? FontWeight.bold : FontWeight.normal,
      letterSpacing: headerStyle ? 0.6 : 0,
    );
    final valueStyle = TextStyle(
      color: headerStyle ? Colors.white38 : _accent,
      fontSize: headerStyle ? 8.5 : 12,
      fontWeight: FontWeight.bold,
      letterSpacing: headerStyle ? 0.6 : 0,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 14, child: Text(rank, style: labelStyle)),
          Expanded(
            child: Text(
              name,
              style: labelStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 20,
            child: Text(
              contrib,
              textAlign: TextAlign.center,
              style: valueStyle,
            ),
          ),
          SizedBox(
            width: 18,
            child: Text(goals, textAlign: TextAlign.center, style: labelStyle),
          ),
          SizedBox(
            width: 18,
            child: Text(
              assists,
              textAlign: TextAlign.center,
              style: labelStyle,
            ),
          ),
          if (minutes != null)
            SizedBox(
              width: 30,
              child: Text(
                minutes,
                textAlign: TextAlign.right,
                style: labelStyle,
              ),
            ),
        ],
      ),
    );
  }
}
