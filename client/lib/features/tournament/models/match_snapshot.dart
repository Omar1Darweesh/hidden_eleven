import 'participant_snapshot.dart';

class CompletedMatchSnapshot {
  final int scoreA;
  final int scoreB;
  // Null unless the match was drawn after regulation and went to penalties.
  final int? penaltyScoreA;
  final int? penaltyScoreB;
  final String explanation;

  const CompletedMatchSnapshot({
    required this.scoreA,
    required this.scoreB,
    this.penaltyScoreA,
    this.penaltyScoreB,
    required this.explanation,
  });

  bool get wasDecidedByPenalties =>
      penaltyScoreA != null && penaltyScoreB != null;

  factory CompletedMatchSnapshot.fromJson(Map<String, dynamic> json) {
    return CompletedMatchSnapshot(
      scoreA: json['scoreA'] as int,
      scoreB: json['scoreB'] as int,
      penaltyScoreA: json['penaltyScoreA'] as int?,
      penaltyScoreB: json['penaltyScoreB'] as int?,
      explanation: json['explanation'] as String,
    );
  }
}

class MatchSnapshot {
  final String matchId;
  final int roundNumber;
  final ParticipantSnapshot participantA;
  final ParticipantSnapshot participantB;
  final String status;
  final CompletedMatchSnapshot? result;
  final String? winnerId;

  const MatchSnapshot({
    required this.matchId,
    required this.roundNumber,
    required this.participantA,
    required this.participantB,
    required this.status,
    this.result,
    this.winnerId,
  });

  factory MatchSnapshot.fromJson(Map<String, dynamic> json) {
    return MatchSnapshot(
      matchId: json['matchId'] as String,
      roundNumber: json['roundNumber'] as int,
      participantA: ParticipantSnapshot.fromJson(
        json['participantA'] as Map<String, dynamic>,
      ),
      participantB: ParticipantSnapshot.fromJson(
        json['participantB'] as Map<String, dynamic>,
      ),
      status: json['status'] as String,
      result: json['result'] != null
          ? CompletedMatchSnapshot.fromJson(
              json['result'] as Map<String, dynamic>,
            )
          : null,
      winnerId: json['winnerId'] as String?,
    );
  }
}
