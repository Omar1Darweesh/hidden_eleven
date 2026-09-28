import 'participant_snapshot.dart';

/// A per-player stat leader entry. Awards can be SHARED (see the tie-rule
/// documentation on the server's `_computeTournamentAwards`) — every category
/// is a list (length 1 in the common case, 2+ when genuinely tied).
class TopScorerEntry {
  final String playerName;
  final String participantId;
  final int goals;
  final int minutesPlayed;

  const TopScorerEntry({
    required this.playerName,
    required this.participantId,
    required this.goals,
    required this.minutesPlayed,
  });

  factory TopScorerEntry.fromJson(Map<String, dynamic> json) => TopScorerEntry(
    playerName: json['playerName'] as String,
    participantId: json['participantId'] as String,
    goals: json['goals'] as int,
    minutesPlayed: json['minutesPlayed'] as int,
  );
}

class TopAssistEntry {
  final String playerName;
  final String participantId;
  final int assists;
  final int minutesPlayed;

  const TopAssistEntry({
    required this.playerName,
    required this.participantId,
    required this.assists,
    required this.minutesPlayed,
  });

  factory TopAssistEntry.fromJson(Map<String, dynamic> json) => TopAssistEntry(
    playerName: json['playerName'] as String,
    participantId: json['participantId'] as String,
    assists: json['assists'] as int,
    minutesPlayed: json['minutesPlayed'] as int,
  );
}

/// goals + assists. A new leaderboard/stat — carries no bonus points of its
/// own (see the product spec).
class TopContributionEntry {
  final String playerName;
  final String participantId;
  final int goals;
  final int assists;
  final int contributions;
  final int minutesPlayed;

  const TopContributionEntry({
    required this.playerName,
    required this.participantId,
    required this.goals,
    required this.assists,
    required this.contributions,
    required this.minutesPlayed,
  });

  factory TopContributionEntry.fromJson(Map<String, dynamic> json) =>
      TopContributionEntry(
        playerName: json['playerName'] as String,
        participantId: json['participantId'] as String,
        goals: json['goals'] as int,
        assists: json['assists'] as int,
        contributions: json['contributions'] as int,
        minutesPlayed: json['minutesPlayed'] as int,
      );
}

/// Per-player award — the individual with the highest average match rating.
/// Same minutes-played tiebreak as the other stat categories, see server docs.
class RatingLeaderEntry {
  final String playerName;
  final String participantId;
  final double avgRating;
  final int minutesPlayed;

  const RatingLeaderEntry({
    required this.playerName,
    required this.participantId,
    required this.avgRating,
    required this.minutesPlayed,
  });

  factory RatingLeaderEntry.fromJson(Map<String, dynamic> json) =>
      RatingLeaderEntry(
        playerName: json['playerName'] as String,
        participantId: json['participantId'] as String,
        avgRating: (json['avgRating'] as num).toDouble(),
        minutesPlayed: json['minutesPlayed'] as int,
      );
}

/// Credited to the actual goalkeeper — never the participant/team name.
/// Carries no bonus points of its own (a leaderboard/stat only).
class CleanSheetEntry {
  final String playerName;
  final String participantId;
  final int cleanSheets;
  final int minutesPlayed;

  const CleanSheetEntry({
    required this.playerName,
    required this.participantId,
    required this.cleanSheets,
    required this.minutesPlayed,
  });

  factory CleanSheetEntry.fromJson(Map<String, dynamic> json) =>
      CleanSheetEntry(
        playerName: json['playerName'] as String,
        participantId: json['participantId'] as String,
        cleanSheets: json['cleanSheets'] as int,
        minutesPlayed: json['minutesPlayed'] as int,
      );
}

/// One line in a participant's tournament-points breakdown, e.g.
/// "Top Scorer (shared) +8". `shared` marks whether that category's award was
/// split among multiple tied winners (never a fake single-winner label).
/// `blocked` marks a category this participant genuinely led/tied for, but
/// which paid no one because an AI participant was among the leaders — the
/// points are 0 for a real reason, not simply absent.
class AwardBonusLine {
  final String label;
  final int points;
  final bool shared;
  final bool blocked;

  const AwardBonusLine({
    required this.label,
    required this.points,
    required this.shared,
    this.blocked = false,
  });

  String get display => blocked
      ? '$label — blocked (AI led)'
      : '$label${shared ? ' (shared)' : ''} +$points';
}

/// The exact tournament award point values used to compute a given result —
/// echoed from the server on the awards payload (Track A Step 5) so the
/// client never duplicates or guesses these numbers. Falls back to the
/// pre-Track-A hardcoded values (`legacyDefault`) when the server hasn't
/// sent `pointsConfig` yet — an older server mid-rolling-deploy — so display
/// never regresses either way.
class TournamentAwardsPointsConfig {
  final int championPoints;
  final int runnerUpPoints;
  final int topScorerBonus;
  final int mostAssistsBonus;
  final int highestRatingBonus;

  const TournamentAwardsPointsConfig({
    required this.championPoints,
    required this.runnerUpPoints,
    required this.topScorerBonus,
    required this.mostAssistsBonus,
    required this.highestRatingBonus,
  });

  /// Pre-Track-A hardcoded values (was: TournamentAwardsModel's static
  /// consts). The single source of truth for "what the client shows when
  /// the server sends nothing" — never duplicated elsewhere.
  static const legacyDefault = TournamentAwardsPointsConfig(
    championPoints: 50,
    runnerUpPoints: 20,
    topScorerBonus: 15,
    mostAssistsBonus: 10,
    highestRatingBonus: 10,
  );

  factory TournamentAwardsPointsConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return legacyDefault;
    return TournamentAwardsPointsConfig(
      championPoints:
          json['championPoints'] as int? ?? legacyDefault.championPoints,
      runnerUpPoints:
          json['runnerUpPoints'] as int? ?? legacyDefault.runnerUpPoints,
      topScorerBonus:
          json['topScorerBonus'] as int? ?? legacyDefault.topScorerBonus,
      mostAssistsBonus:
          json['mostAssistsBonus'] as int? ?? legacyDefault.mostAssistsBonus,
      highestRatingBonus:
          json['highestRatingBonus'] as int? ??
          legacyDefault.highestRatingBonus,
    );
  }
}

class TournamentAwardsModel {
  // Scoring system — must mirror the server's single source of truth in
  // GameService._computeTournamentAwards. Bonuses stack additively per
  // participant (e.g. the champion's own top scorer earns champion+topScorer).
  // A tied category is SHARED: its bonus is split equally among every tied
  // winner, rounded UP, so nobody in the same tie ever receives less than
  // another (the split can exceed the nominal pool — that's expected). The
  // actual point VALUES live on `pointsConfig` (admin-configurable, Track A)
  // rather than as constants here — see TournamentAwardsPointsConfig.

  final ParticipantSnapshot champion;
  final ParticipantSnapshot runnerUp;
  final List<TopScorerEntry> topScorer;
  final List<TopAssistEntry> mostAssists;
  final List<TopContributionEntry> topContributions;
  final List<RatingLeaderEntry> highestAvgRating;
  final List<CleanSheetEntry> cleanSheets;
  final Map<String, int> pointsAwarded;

  /// Category labels (e.g. "Top Scorer") where an AI participant was among
  /// the leaders, so the bonus paid no human at all this tournament.
  final List<String> blockedCategories;

  /// The exact point values the server used to compute this result.
  final TournamentAwardsPointsConfig pointsConfig;

  const TournamentAwardsModel({
    required this.champion,
    required this.runnerUp,
    this.topScorer = const [],
    this.mostAssists = const [],
    this.topContributions = const [],
    this.highestAvgRating = const [],
    this.cleanSheets = const [],
    this.blockedCategories = const [],
    this.pointsConfig = TournamentAwardsPointsConfig.legacyDefault,
    required this.pointsAwarded,
  });

  // ── Convenience getters for simple "headline" summaries (the tournament
  // complete screen, admin panel, and result banner) that just want one
  // display string — gracefully joins names when the award is shared rather
  // than silently picking one winner. ──────────────────────────────────────
  String? get topScorerName =>
      topScorer.isEmpty ? null : topScorer.map((e) => e.playerName).join(' & ');
  int? get topScorerGoals => topScorer.isEmpty ? null : topScorer.first.goals;

  String? get mostAssistsName => mostAssists.isEmpty
      ? null
      : mostAssists.map((e) => e.playerName).join(' & ');
  int? get mostAssistsCount =>
      mostAssists.isEmpty ? null : mostAssists.first.assists;

  String? get highestRatingName => highestAvgRating.isEmpty
      ? null
      : highestAvgRating.map((e) => e.playerName).join(' & ');
  double? get highestRatingValue =>
      highestAvgRating.isEmpty ? null : highestAvgRating.first.avgRating;

  /// This participant's award-category bonus lines, in scoring-system order.
  /// The single source of truth for "how was this total built" — used by
  /// both the tournament leaderboard and the result page so the two never
  /// disagree. A category is marked `shared` (and its `points` is the actual
  /// rounded-up per-winner share, not the nominal pool) whenever more than
  /// one participant tied for it.
  List<AwardBonusLine> breakdownFor(String participantId) {
    final out = <AwardBonusLine>[];
    if (participantId == champion.participantId) {
      out.add(
        AwardBonusLine(
          label: 'Champion',
          points: pointsConfig.championPoints,
          shared: false,
        ),
      );
    }
    if (participantId == runnerUp.participantId) {
      out.add(
        AwardBonusLine(
          label: 'Runner-up',
          points: pointsConfig.runnerUpPoints,
          shared: false,
        ),
      );
    }
    void addShared(String label, List<String> winnerIds, int pool) {
      if (winnerIds.isEmpty || !winnerIds.contains(participantId)) return;
      // This participant genuinely led/tied for the category, but an AI
      // participant among the leaders blocked the whole payout — show that
      // plainly instead of a fabricated bonus (or silently nothing).
      if (blockedCategories.contains(label)) {
        out.add(
          AwardBonusLine(
            label: label,
            points: 0,
            shared: winnerIds.length > 1,
            blocked: true,
          ),
        );
        return;
      }
      final perWinner = (pool / winnerIds.length).ceil();
      out.add(
        AwardBonusLine(
          label: label,
          points: perWinner,
          shared: winnerIds.length > 1,
        ),
      );
    }

    addShared(
      'Top Scorer',
      topScorer.map((e) => e.participantId).toList(),
      pointsConfig.topScorerBonus,
    );
    addShared(
      'Most Assists',
      mostAssists.map((e) => e.participantId).toList(),
      pointsConfig.mostAssistsBonus,
    );
    addShared(
      'Best Rating',
      highestAvgRating.map((e) => e.participantId).toList(),
      pointsConfig.highestRatingBonus,
    );
    return out;
  }

  factory TournamentAwardsModel.fromJson(Map<String, dynamic> json) {
    final points = <String, int>{};
    final rawPoints = json['pointsAwarded'] as Map<String, dynamic>? ?? {};
    rawPoints.forEach((k, v) => points[k] = (v as num).toInt());

    final topScorerRaw = json['topScorer'] as List<dynamic>? ?? const [];
    final mostAssistsRaw = json['mostAssists'] as List<dynamic>? ?? const [];
    final topContributionsRaw =
        json['topContributions'] as List<dynamic>? ?? const [];
    final highestRatingRaw =
        json['highestAvgRating'] as List<dynamic>? ?? const [];
    final cleanSheetsRaw = json['cleanSheets'] as List<dynamic>? ?? const [];
    final blockedRaw = json['blockedCategories'] as List<dynamic>? ?? const [];

    return TournamentAwardsModel(
      champion: ParticipantSnapshot.fromJson(
        json['champion'] as Map<String, dynamic>,
      ),
      runnerUp: ParticipantSnapshot.fromJson(
        json['runnerUp'] as Map<String, dynamic>,
      ),
      topScorer: topScorerRaw
          .map((e) => TopScorerEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      mostAssists: mostAssistsRaw
          .map((e) => TopAssistEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      topContributions: topContributionsRaw
          .map((e) => TopContributionEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      highestAvgRating: highestRatingRaw
          .map((e) => RatingLeaderEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      cleanSheets: cleanSheetsRaw
          .map((e) => CleanSheetEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      blockedCategories: blockedRaw.map((e) => e as String).toList(),
      pointsConfig: TournamentAwardsPointsConfig.fromJson(
        json['pointsConfig'] as Map<String, dynamic>?,
      ),
      pointsAwarded: points,
    );
  }
}
