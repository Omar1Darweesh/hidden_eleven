enum TournamentParticipantKind { real, ai }

class ParticipantSnapshot {
  final String participantId;
  final TournamentParticipantKind kind;
  final String displayName;
  final double overallRating;

  /// Club badge URL — populated for AI participants when the pool has one.
  final String? clubLogoUrl;

  const ParticipantSnapshot({
    required this.participantId,
    required this.kind,
    required this.displayName,
    required this.overallRating,
    this.clubLogoUrl,
  });

  bool get isAi => kind == TournamentParticipantKind.ai;

  factory ParticipantSnapshot.fromJson(Map<String, dynamic> json) {
    return ParticipantSnapshot(
      participantId: json['participantId'] as String,
      kind: json['kind'] == 'ai'
          ? TournamentParticipantKind.ai
          : TournamentParticipantKind.real,
      displayName: json['displayName'] as String,
      overallRating: (json['overallRating'] as num).toDouble(),
      clubLogoUrl: json['clubLogoUrl'] as String?,
    );
  }
}
