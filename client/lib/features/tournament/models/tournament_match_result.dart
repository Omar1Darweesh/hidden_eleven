class MatchStatsModel {
  final int possessionA;
  final int shotsA;
  final int shotsOnTargetA;
  final int bigChancesA;
  final int shotsB;
  final int shotsOnTargetB;
  final int bigChancesB;

  const MatchStatsModel({
    required this.possessionA,
    required this.shotsA,
    required this.shotsOnTargetA,
    required this.bigChancesA,
    required this.shotsB,
    required this.shotsOnTargetB,
    required this.bigChancesB,
  });

  factory MatchStatsModel.fromJson(Map<String, dynamic> json) {
    return MatchStatsModel(
      possessionA: (json['possessionA'] as num).toInt(),
      shotsA: (json['shotsA'] as num).toInt(),
      shotsOnTargetA: (json['shotsOnTargetA'] as num).toInt(),
      bigChancesA: (json['bigChancesA'] as num).toInt(),
      shotsB: (json['shotsB'] as num).toInt(),
      shotsOnTargetB: (json['shotsOnTargetB'] as num).toInt(),
      bigChancesB: (json['bigChancesB'] as num).toInt(),
    );
  }
}

class TournamentMatchResult {
  final String matchId;
  final int roundNumber;
  final int scoreA;
  final int scoreB;
  final String winnerId;
  // Null unless the match was drawn after regulation and went to penalties.
  final int? penaltyScoreA;
  final int? penaltyScoreB;
  final String explanation;
  final Map<String, double> playerRatings;
  final MatchStatsModel? stats;

  const TournamentMatchResult({
    required this.matchId,
    required this.roundNumber,
    required this.scoreA,
    required this.scoreB,
    required this.winnerId,
    this.penaltyScoreA,
    this.penaltyScoreB,
    required this.explanation,
    required this.playerRatings,
    this.stats,
  });

  bool get wasDecidedByPenalties =>
      penaltyScoreA != null && penaltyScoreB != null;

  factory TournamentMatchResult.fromJson(Map<String, dynamic> json) {
    final ratings = <String, double>{};
    final raw = json['playerRatings'] as Map<String, dynamic>? ?? {};
    raw.forEach((k, v) => ratings[k] = (v as num).toDouble());
    return TournamentMatchResult(
      matchId: json['matchId'] as String,
      roundNumber: json['roundNumber'] as int,
      scoreA: json['scoreA'] as int,
      scoreB: json['scoreB'] as int,
      winnerId: json['winnerId'] as String,
      penaltyScoreA: json['penaltyScoreA'] as int?,
      penaltyScoreB: json['penaltyScoreB'] as int?,
      explanation: json['explanation'] as String,
      playerRatings: ratings,
      stats: json['stats'] != null
          ? MatchStatsModel.fromJson(json['stats'] as Map<String, dynamic>)
          : null,
    );
  }
}
