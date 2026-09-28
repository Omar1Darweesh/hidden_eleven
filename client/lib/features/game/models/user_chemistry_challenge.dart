import 'package:flutter/foundation.dart';

enum UserChallengeType {
  nationCount,
  twoNationsCombo,
  clubCount,
  twoClubsCombo,
  leagueCount,
  twoLeaguesCombo,
  nationAndClub,
  positionGroup,
  allChallengesMet,
}

extension UserChallengeTypeX on UserChallengeType {
  static UserChallengeType fromString(String s) => switch (s) {
    'NATION_COUNT' => UserChallengeType.nationCount,
    'TWO_NATIONS_COMBO' => UserChallengeType.twoNationsCombo,
    'CLUB_COUNT' => UserChallengeType.clubCount,
    'TWO_CLUBS_COMBO' => UserChallengeType.twoClubsCombo,
    'LEAGUE_COUNT' => UserChallengeType.leagueCount,
    'TWO_LEAGUES_COMBO' => UserChallengeType.twoLeaguesCombo,
    'NATION_AND_CLUB' => UserChallengeType.nationAndClub,
    'POSITION_GROUP' => UserChallengeType.positionGroup,
    'ALL_CHALLENGES_MET' => UserChallengeType.allChallengesMet,
    _ => UserChallengeType.positionGroup,
  };

  bool get isCombo =>
      this == UserChallengeType.twoNationsCombo ||
      this == UserChallengeType.twoClubsCombo ||
      this == UserChallengeType.twoLeaguesCombo;
}

@immutable
class ChallengeConditionProgress {
  const ChallengeConditionProgress({
    required this.label,
    required this.current,
    required this.required,
    required this.satisfied,
  });

  final String label;
  final int current;
  final int required;
  final bool satisfied;

  factory ChallengeConditionProgress.fromJson(Map<String, dynamic> json) {
    return ChallengeConditionProgress(
      label: json['label'] as String? ?? '',
      current: json['current'] as int? ?? 0,
      required: json['required'] as int? ?? 1,
      satisfied: json['satisfied'] as bool? ?? false,
    );
  }
}

@immutable
class UserChemistryChallenge {
  const UserChemistryChallenge({
    required this.type,
    required this.params,
    required this.label,
    required this.reward,
    required this.satisfied,
    required this.current,
    required this.required,
    this.conditions = const [],
  });

  final UserChallengeType type;
  final Map<String, dynamic> params;
  final String label;
  final int reward;
  final bool satisfied;
  final int current;
  final int required;

  /// Non-empty only for TWO_* combo types.
  final List<ChallengeConditionProgress> conditions;

  factory UserChemistryChallenge.fromJson(Map<String, dynamic> json) {
    final rawConditions = json['conditions'] as List<dynamic>?;
    return UserChemistryChallenge(
      type: UserChallengeTypeX.fromString(json['type'] as String? ?? ''),
      params: (json['params'] as Map<String, dynamic>?) ?? {},
      label: json['label'] as String? ?? '',
      reward: json['reward'] as int? ?? 5,
      satisfied: json['satisfied'] as bool? ?? false,
      current: json['current'] as int? ?? 0,
      required: json['required'] as int? ?? 1,
      conditions: rawConditions == null
          ? const []
          : rawConditions
                .map(
                  (e) => ChallengeConditionProgress.fromJson(
                    e as Map<String, dynamic>,
                  ),
                )
                .toList(),
    );
  }
}
