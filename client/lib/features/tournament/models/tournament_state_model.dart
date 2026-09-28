import 'tournament_phase.dart';
import 'round_snapshot.dart';
import 'tournament_awards_model.dart';

class TournamentStateModel {
  final TournamentPhase phase;
  final int currentRound;
  final int totalRounds;
  final List<String> readyPlayerIds;
  final int? readyDeadlineAt;
  final int? bracketRevealAt;
  final List<RoundSnapshot> rounds;
  final TournamentAwardsModel? awards;

  const TournamentStateModel({
    required this.phase,
    required this.currentRound,
    required this.totalRounds,
    required this.readyPlayerIds,
    this.readyDeadlineAt,
    this.bracketRevealAt,
    required this.rounds,
    this.awards,
  });

  factory TournamentStateModel.fromJson(Map<String, dynamic> json) {
    return TournamentStateModel(
      phase: TournamentPhase.fromJson(json['phase'] as String),
      currentRound: json['currentRound'] as int,
      totalRounds: json['totalRounds'] as int,
      readyPlayerIds: List<String>.from(json['readyPlayerIds'] as List),
      readyDeadlineAt: json['readyDeadlineAt'] as int?,
      bracketRevealAt: json['bracketRevealAt'] as int?,
      rounds: (json['bracket']['rounds'] as List)
          .map((r) => RoundSnapshot.fromJson(r as Map<String, dynamic>))
          .toList(),
      awards: json['awards'] != null
          ? TournamentAwardsModel.fromJson(
              json['awards'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}
