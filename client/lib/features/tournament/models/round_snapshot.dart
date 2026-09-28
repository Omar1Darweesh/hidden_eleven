import 'match_snapshot.dart';

class RoundSnapshot {
  final int roundNumber;
  final String label;
  final String status;
  final List<MatchSnapshot> matches;

  const RoundSnapshot({
    required this.roundNumber,
    required this.label,
    required this.status,
    required this.matches,
  });

  factory RoundSnapshot.fromJson(Map<String, dynamic> json) {
    return RoundSnapshot(
      roundNumber: json['roundNumber'] as int,
      label: json['label'] as String,
      status: json['status'] as String,
      matches: (json['matches'] as List)
          .map((m) => MatchSnapshot.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }
}
