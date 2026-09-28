import 'package:flutter/foundation.dart';

enum ChemistryBonusType {
  sameClub,
  sameNation,
  sameLeague,
  positionGroup,
  clubAndPosition,
  nationAndPosition,
}

extension ChemistryBonusTypeX on ChemistryBonusType {
  static ChemistryBonusType fromString(String s) => switch (s) {
    'SAME_CLUB' => ChemistryBonusType.sameClub,
    'SAME_NATION' => ChemistryBonusType.sameNation,
    'SAME_LEAGUE' => ChemistryBonusType.sameLeague,
    'POSITION_GROUP' => ChemistryBonusType.positionGroup,
    'CLUB_AND_POSITION' => ChemistryBonusType.clubAndPosition,
    'NATION_AND_POSITION' => ChemistryBonusType.nationAndPosition,
    _ => ChemistryBonusType.sameLeague,
  };
}

enum ChemistryTier { easy, medium, hard }

extension ChemistryTierX on ChemistryTier {
  static ChemistryTier fromString(String s) => switch (s) {
    'easy' => ChemistryTier.easy,
    'medium' => ChemistryTier.medium,
    'hard' => ChemistryTier.hard,
    _ => ChemistryTier.easy,
  };
}

@immutable
class ChemistryBonus {
  const ChemistryBonus({
    required this.type,
    required this.params,
    required this.label,
    required this.tier,
    required this.reward,
  });

  final ChemistryBonusType type;
  final Map<String, dynamic> params;
  final String label;

  /// Difficulty tier — drives the reward (easy +2 / medium +4 / hard +6).
  final ChemistryTier tier;

  /// Points awarded when this challenge is satisfied.
  final int reward;

  factory ChemistryBonus.fromJson(Map<String, dynamic> json) {
    return ChemistryBonus(
      type: ChemistryBonusTypeX.fromString(json['type'] as String? ?? ''),
      params: (json['params'] as Map<String, dynamic>?) ?? {},
      label: json['label'] as String? ?? '',
      tier: ChemistryTierX.fromString(json['tier'] as String? ?? 'easy'),
      reward: (json['reward'] as num?)?.toInt() ?? 0,
    );
  }
}
