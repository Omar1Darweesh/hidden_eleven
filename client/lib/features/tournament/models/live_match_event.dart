class LiveMatchEvent {
  final String matchId;
  final int roundNumber;
  final int minute;
  final String type;
  final String teamParticipantId;
  final String playerName;
  final double playerRating;
  final String? assistPlayerName;
  final int currentScoreA;
  final int currentScoreB;

  const LiveMatchEvent({
    required this.matchId,
    required this.roundNumber,
    required this.minute,
    required this.type,
    required this.teamParticipantId,
    required this.playerName,
    required this.playerRating,
    this.assistPlayerName,
    required this.currentScoreA,
    required this.currentScoreB,
  });

  factory LiveMatchEvent.fromJson(Map<String, dynamic> json) {
    final event = json['event'] as Map<String, dynamic>;
    return LiveMatchEvent(
      matchId: json['matchId'] as String,
      roundNumber: json['roundNumber'] as int,
      minute: event['minute'] as int,
      type: event['type'] as String,
      teamParticipantId: event['teamParticipantId'] as String,
      playerName: event['playerName'] as String,
      playerRating: (event['playerRating'] as num).toDouble(),
      assistPlayerName: event['assistPlayerName'] as String?,
      currentScoreA: json['currentScoreA'] as int,
      currentScoreB: json['currentScoreB'] as int,
    );
  }
}
