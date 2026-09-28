import 'package:hidden_eleven/features/game/models/chemistry_bonus.dart';
import 'package:hidden_eleven/features/game/models/game_state.dart';

// Position groups matching the server definition
const _defPositions = {'GK', 'LB', 'CB', 'RB'};
const _midPositions = {'CDM', 'CM', 'CAM', 'LM', 'RM'};
const _atkPositions = {'LW', 'RW', 'CF', 'ST'};

Set<String> _groupPositions(String? group) => switch (group) {
  'DEF' => _defPositions,
  'MID' => _midPositions,
  'ATK' => _atkPositions,
  _ => const <String>{},
};

/// Simple data class representing a placed card for evaluation purposes.
/// Avoids coupling the evaluator to PitchSlot directly.
class LineupCard {
  const LineupCard({
    required this.club,
    required this.nationality,
    required this.league,
    required this.slotPosition,
  });

  final String? club;
  final String? nationality;
  final String? league;
  final String slotPosition; // basePositionType of the slot

  static LineupCard fromSlot(PitchSlot slot) => LineupCard(
    club: slot.cardClub,
    nationality: slot.cardNationality,
    league: slot.cardLeague,
    slotPosition: slot.basePositionType,
  );
}

/// Clubs whose cards always carry full chemistry — same "Icons/Heroes never
/// lose chemistry" mechanic real FIFA/FC uses. Mirrors
/// scoring.ts's `CHEMISTRY_EXEMPT_CLUBS`; keep both lists in sync.
const Set<String> chemistryExemptClubs = {'Icons', 'Heroes'};

/// Evaluates a card's 3 tiered chemistry challenges against the current lineup.
///
/// Mirrors the server logic in scoring.ts (`evaluateCardBonus`) exactly so the
/// overlay a player sees matches the points credited at scoring time.
class ChemistryEvaluator {
  const ChemistryEvaluator._();

  /// Returns indices (0, 1, 2) of satisfied challenges. [ownerClub] is the
  /// club of the card these bonuses belong to — when it's chemistry-exempt
  /// (Icons/Heroes), every challenge counts as satisfied regardless of the
  /// rest of the lineup.
  static List<int> activeSlotIndices(
    List<ChemistryBonus> bonuses,
    List<LineupCard> lineup, {
    String? ownerClub,
  }) {
    if (ownerClub != null && chemistryExemptClubs.contains(ownerClub)) {
      return List<int>.generate(bonuses.length, (i) => i);
    }
    final result = <int>[];
    for (var i = 0; i < bonuses.length; i++) {
      if (isSatisfied(bonuses[i], lineup)) result.add(i);
    }
    return result;
  }

  /// Sum of rewards for every satisfied challenge on this card (0..12).
  /// See [activeSlotIndices] for [ownerClub].
  static int earnedReward(
    List<ChemistryBonus> bonuses,
    List<LineupCard> lineup, {
    String? ownerClub,
  }) {
    if (ownerClub != null && chemistryExemptClubs.contains(ownerClub)) {
      var total = 0;
      for (final b in bonuses) {
        total += b.reward;
      }
      return total;
    }
    var total = 0;
    for (final b in bonuses) {
      if (isSatisfied(b, lineup)) total += b.reward;
    }
    return total;
  }

  /// Returns progress toward satisfying the given challenge.
  /// For compound (AND) challenges, current/required is the combined progress
  /// across both sub-conditions. Used for the amber partial-progress bar.
  static ({int current, int required}) progressOf(
    ChemistryBonus bonus,
    List<LineupCard> lineup,
  ) {
    final p = bonus.params;
    switch (bonus.type) {
      case ChemistryBonusType.sameClub:
        final club = p['club'] as String?;
        final count = (p['count'] as num?)?.toInt() ?? 2;
        if (club == null) return (current: 0, required: count);
        return (
          current: lineup.where((c) => c.club == club).length.clamp(0, count),
          required: count,
        );

      case ChemistryBonusType.sameNation:
        final nation = p['nation'] as String?;
        final count = (p['count'] as num?)?.toInt() ?? 2;
        if (nation == null) return (current: 0, required: count);
        return (
          current: lineup
              .where((c) => c.nationality == nation)
              .length
              .clamp(0, count),
          required: count,
        );

      case ChemistryBonusType.sameLeague:
        final league = p['league'] as String?;
        final count = (p['count'] as num?)?.toInt() ?? 3;
        if (league == null) return (current: 0, required: count);
        return (
          current: lineup
              .where((c) => c.league == league)
              .length
              .clamp(0, count),
          required: count,
        );

      case ChemistryBonusType.positionGroup:
        final positions = _groupPositions(p['group'] as String?);
        final count = (p['count'] as num?)?.toInt() ?? 2;
        return (
          current: lineup
              .where((c) => positions.contains(c.slotPosition))
              .length
              .clamp(0, count),
          required: count,
        );

      case ChemistryBonusType.clubAndPosition:
        final club = p['club'] as String?;
        final clubCount = (p['clubCount'] as num?)?.toInt() ?? 2;
        final positions = _groupPositions(p['group'] as String?);
        final groupCount = (p['groupCount'] as num?)?.toInt() ?? 2;
        final cClub = club == null
            ? 0
            : lineup.where((c) => c.club == club).length.clamp(0, clubCount);
        final cPos = lineup
            .where((c) => positions.contains(c.slotPosition))
            .length
            .clamp(0, groupCount);
        return (current: cClub + cPos, required: clubCount + groupCount);

      case ChemistryBonusType.nationAndPosition:
        final nation = p['nation'] as String?;
        final nationCount = (p['nationCount'] as num?)?.toInt() ?? 2;
        final positions = _groupPositions(p['group'] as String?);
        final groupCount = (p['groupCount'] as num?)?.toInt() ?? 2;
        final cNat = nation == null
            ? 0
            : lineup
                  .where((c) => c.nationality == nation)
                  .length
                  .clamp(0, nationCount);
        final cPos = lineup
            .where((c) => positions.contains(c.slotPosition))
            .length
            .clamp(0, groupCount);
        return (current: cNat + cPos, required: nationCount + groupCount);
    }
  }

  /// Returns true if the given challenge is fully satisfied by the lineup.
  static bool isSatisfied(ChemistryBonus bonus, List<LineupCard> lineup) {
    final p = bonus.params;
    switch (bonus.type) {
      case ChemistryBonusType.sameClub:
        final club = p['club'] as String?;
        final count = (p['count'] as num?)?.toInt() ?? 2;
        if (club == null) return false;
        return lineup.where((c) => c.club == club).length >= count;

      case ChemistryBonusType.sameNation:
        final nation = p['nation'] as String?;
        final count = (p['count'] as num?)?.toInt() ?? 2;
        if (nation == null) return false;
        return lineup.where((c) => c.nationality == nation).length >= count;

      case ChemistryBonusType.sameLeague:
        final league = p['league'] as String?;
        final count = (p['count'] as num?)?.toInt() ?? 3;
        if (league == null) return false;
        return lineup.where((c) => c.league == league).length >= count;

      case ChemistryBonusType.positionGroup:
        final positions = _groupPositions(p['group'] as String?);
        final count = (p['count'] as num?)?.toInt() ?? 2;
        return lineup.where((c) => positions.contains(c.slotPosition)).length >=
            count;

      case ChemistryBonusType.clubAndPosition:
        final club = p['club'] as String?;
        final clubCount = (p['clubCount'] as num?)?.toInt() ?? 2;
        final positions = _groupPositions(p['group'] as String?);
        final groupCount = (p['groupCount'] as num?)?.toInt() ?? 2;
        if (club == null) return false;
        return lineup.where((c) => c.club == club).length >= clubCount &&
            lineup.where((c) => positions.contains(c.slotPosition)).length >=
                groupCount;

      case ChemistryBonusType.nationAndPosition:
        final nation = p['nation'] as String?;
        final nationCount = (p['nationCount'] as num?)?.toInt() ?? 2;
        final positions = _groupPositions(p['group'] as String?);
        final groupCount = (p['groupCount'] as num?)?.toInt() ?? 2;
        if (nation == null) return false;
        return lineup.where((c) => c.nationality == nation).length >=
                nationCount &&
            lineup.where((c) => positions.contains(c.slotPosition)).length >=
                groupCount;
    }
  }
}
