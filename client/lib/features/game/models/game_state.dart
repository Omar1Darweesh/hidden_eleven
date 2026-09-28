import 'package:flutter/foundation.dart';
import 'package:hidden_eleven/features/game/models/ability.dart';
import 'package:hidden_eleven/features/game/models/chemistry_bonus.dart';
import 'package:hidden_eleven/features/game/models/user_chemistry_challenge.dart';

@immutable
class GamePlayer {
  const GamePlayer({
    required this.id,
    required this.displayName,
    required this.isHost,
    this.isConnected = true,
  });

  final String id;
  final String displayName;
  final bool isHost;
  final bool isConnected;
}

@immutable
class GameTurn {
  const GameTurn({
    required this.turnId,
    required this.phase,
    required this.activePlayerId,
    this.activeSlotIndex,
    this.revealPickerPlayerId,
    this.turnStartedAt,
    this.turnDurationSeconds,
    this.candidates = const [],
  });

  final String turnId;
  final String phase;
  final String activePlayerId;
  final int? activeSlotIndex;

  /// Non-null only during `hidden_pick_reveal`. The player who just picked and
  /// must press Continue (or wait for the 5-second auto-advance).
  final String? revealPickerPlayerId;

  /// Wall-clock time the current turn timer was armed. Null when no timer.
  final DateTime? turnStartedAt;

  /// How many seconds the timer runs for. Null when no timer.
  final int? turnDurationSeconds;

  /// The `selecting_card` candidate pool — durable and part of every
  /// game_state, but only ever non-empty for the active player's own
  /// snapshot (see game.service.ts's buildSnapshot). This is what lets a
  /// refresh/reconnect mid selecting_card restore the exact candidate list
  /// instead of depending on the one-off `slot_candidates` event, which only
  /// ever fires once, live, right after the pick_slot that created it.
  final List<CandidateCard> candidates;
}

@immutable
class PitchSlot {
  const PitchSlot({
    required this.index,
    required this.label,
    required this.basePositionType,
    this.cardPlayerName,
    this.cardRating,
    this.cardId,
    this.cardImageUrl,
    this.cardClub,
    this.cardClubLogoUrl,
    this.cardPrimaryColor,
    this.cardSecondaryColor,
    this.cardTertiaryColor,
    this.cardKitPattern,
    this.cardStyle,
    this.cardKitNumber,
    this.cardNationality,
    this.cardAltPositions = const [],
    this.cardNaturalPositions = const [],
    this.cardPace = 0,
    this.cardShooting = 0,
    this.cardPassing = 0,
    this.cardDribbling = 0,
    this.cardDefending = 0,
    this.cardPhysical = 0,
    this.cardLeague,
    this.cardChemistryBonuses = const [],
    this.isCaptain = false,
    this.isRedCarded = false,
    this.isSubSwapped = false,
    this.isCoached = false,
  });

  final int index;
  final String label;
  final String basePositionType;

  /// This slot's card was captained by its owner (chemistry doubled).
  final bool isCaptain;

  /// This slot's card was red-carded by an opponent (chemistry nullified;
  /// rating still counts toward line averages).
  final bool isRedCarded;

  /// This slot's card came from / went to an opponent via a Sub-card swap.
  final bool isSubSwapped;

  /// This slot's card was given an extra playable position by a Coach card.
  /// The coached position is already merged into [cardNaturalPositions]; this
  /// flag exists so the card can also show a Coach badge.
  final bool isCoached;
  final String? cardPlayerName;
  final int? cardRating;
  final String? cardId;
  final String? cardImageUrl;
  final String? cardClub;
  final String? cardClubLogoUrl;
  final String? cardPrimaryColor;
  final String? cardSecondaryColor;
  final String? cardTertiaryColor;
  final String? cardKitPattern;

  /// Special card frame ('icon' | 'hero' | null = normal rating-tier frame).
  final String? cardStyle;
  final int? cardKitNumber;
  final String? cardNationality;
  final List<String> cardAltPositions;

  /// The player's full natural position set (primary + alts), used to validate
  /// whether this card legally fits a slot when rearranging the lineup.
  final List<String> cardNaturalPositions;
  final String? cardLeague;

  /// Effective natural-position set, falling back to base+alt for older cards.
  List<String> get effectiveNaturalPositions => cardNaturalPositions.isNotEmpty
      ? cardNaturalPositions
      : [basePositionType, ...cardAltPositions];

  /// True if the card currently in this slot legally fits the slot's required
  /// position (primary or alternate). Empty slots are considered valid.
  bool get cardFitsSlot =>
      !isFilled || effectiveNaturalPositions.contains(basePositionType);
  final List<ChemistryBonus> cardChemistryBonuses;
  final int cardPace;
  final int cardShooting;
  final int cardPassing;
  final int cardDribbling;
  final int cardDefending;
  final int cardPhysical;

  bool get isFilled => cardPlayerName != null;
}

@immutable
class PlayerPitch {
  const PlayerPitch({
    required this.playerId,
    required this.slots,
    required this.filledCount,
  });

  final String playerId;
  final List<PitchSlot> slots;
  final int filledCount;
}

@immutable
class CandidateCard {
  const CandidateCard({
    required this.cardId,
    required this.playerName,
    required this.basePositionType,
    required this.rating,
    this.nationality,
    this.club,
    this.clubLogoUrl,
    this.primaryColor,
    this.secondaryColor,
    this.tertiaryColor,
    this.kitPattern,
    this.cardStyle,
    this.kitNumber,
    this.altPositions = const [],
    this.naturalPositions = const [],
    this.imageUrl,
    this.pace = 0,
    this.shooting = 0,
    this.passing = 0,
    this.dribbling = 0,
    this.defending = 0,
    this.physical = 0,
    this.league,
    this.chemistryBonuses = const [],
  });

  final String cardId;
  final String playerName;

  /// The base position type of the SLOT this card was drafted for.
  final String basePositionType;
  final int rating;
  final String? nationality;
  final String? club;
  final String? clubLogoUrl;
  final String? primaryColor;
  final String? secondaryColor;
  final String? tertiaryColor;
  final String? kitPattern;

  /// Special card frame ('icon' | 'hero' | null = normal rating-tier frame).
  /// See CardTier.forCard.
  final String? cardStyle;
  final int? kitNumber;
  final List<String> altPositions;

  /// The player's actual positions (primary first), independent of the slot.
  final List<String> naturalPositions;
  final String? imageUrl;
  final int pace;
  final int shooting;
  final int passing;
  final int dribbling;
  final int defending;
  final int physical;
  final String? league;
  final List<ChemistryBonus> chemistryBonuses;

  /// Player's real primary position (falls back to basePositionType for old cards).
  String get primaryPosition =>
      naturalPositions.isNotEmpty ? naturalPositions.first : basePositionType;

  /// Alt positions derived from naturalPositions (all except primary).
  List<String> get naturalAltPositions =>
      naturalPositions.length > 1 ? naturalPositions.sublist(1) : altPositions;
}

/// Per-slot metadata broadcast by the server during the hidden_pick phase.
/// [card] is non-null for all players as soon as the slot is taken — the card
/// is revealed to everyone immediately upon selection.
@immutable
class HiddenSlotInfo {
  const HiddenSlotInfo({
    required this.slotIndex,
    this.pickedByPlayerName,
    this.card,
  });

  final int slotIndex;
  final String? pickedByPlayerName;
  final CandidateCard? card;
}

@immutable
class SlotCandidatesData {
  const SlotCandidatesData({required this.turnId, required this.candidates});

  final String turnId;
  final List<CandidateCard> candidates;
}

/// One line item in a ScoreBreakdown's itemized explanation (see `lines`).
@immutable
class ScoreBreakdownLine {
  const ScoreBreakdownLine({
    required this.key,
    required this.label,
    required this.amount,
    this.detail,
  });

  final String key;
  final String label;

  /// Signed; penalties are negative.
  final int amount;
  final String? detail;
}

@immutable
class ScoreBreakdown {
  const ScoreBreakdown({
    required this.defAvg,
    required this.midAvg,
    required this.atkAvg,
    required this.linesTotal,
    required this.userChemTotal,
    required this.cardChemTotal,
    this.lineLeaderBonus = 0,
    this.captainBonus = 0,
    this.yellowPenalty = 0,
    this.redApplied = false,
    required this.finalScore,
    this.scoringConfigVersion = 0,
    this.lines = const [],
  });

  final int defAvg;
  final int midAvg;
  final int atkAvg;

  /// Sum of the three line averages: defAvg + midAvg + atkAvg.
  final int linesTotal;
  final int userChemTotal;
  final int cardChemTotal;
  final int lineLeaderBonus;

  /// Extra card-chem from a Captain card doubling one player.
  final int captainBonus;

  /// Points docked by Yellow card(s) aimed at this player.
  final int yellowPenalty;

  /// True if a Red card disabled one of this player's cards.
  final bool redApplied;
  final double finalScore;

  /// Which published scoring-config version scored this game. 0 = unknown/not
  /// applicable (e.g. a payload from before this field existed).
  final int scoringConfigVersion;

  /// Itemized, human-readable explanation of finalScore — same source of
  /// truth as the scalar fields above. Empty on a payload from before this
  /// field existed; callers should fall back to the collapsed total in that
  /// case (see PointsBreakdownCard).
  final List<ScoreBreakdownLine> lines;
}

/// Lightweight in-game preview of the local player's score.
@immutable
class ScoringPreview {
  const ScoringPreview({
    required this.defAvg,
    required this.midAvg,
    required this.atkAvg,
    required this.linesTotal,
    required this.userChallenges,
    required this.userChemTotal,
    required this.cardChemTotal,
    this.lineLeaderBonus = 0,
    required this.estimatedScore,
  });

  final int defAvg;
  final int midAvg;
  final int atkAvg;

  /// Sum of the three line averages: defAvg + midAvg + atkAvg.
  final int linesTotal;
  final List<UserChemistryChallenge> userChallenges;
  final int userChemTotal;
  final int cardChemTotal;
  final int lineLeaderBonus;
  final double estimatedScore;
}

@immutable
class PlayerResult {
  const PlayerResult({
    required this.playerId,
    required this.displayName,
    required this.rank,
    this.score,
    this.scoreBreakdown,
  });

  final String playerId;
  final String displayName;
  final int rank;
  final int? score;
  final ScoreBreakdown? scoreBreakdown;
}

@immutable
class SubSlot {
  const SubSlot({
    required this.positionGroup,
    this.spinResultClub,
    this.chosenPlayerId,
    this.chosenPlayerName,
    this.chosenPlayerRating,
    this.chosenPlayerPosition,
    this.swappedSlotIndex,
    this.benchedPlayerId,
    this.benchedPlayerName,
    this.benchedPlayerRating,
    this.benchedPlayerPosition,
    this.benchedImageUrl,
    this.benchedClub,
    this.benchedClubLogoUrl,
    this.benchedPrimaryColor,
    this.benchedSecondaryColor,
    this.benchedTertiaryColor,
    this.benchedKitPattern,
    this.benchedCardStyle,
    this.benchedKitNumber,
    this.benchedNationality,
    this.benchedPace,
    this.benchedShooting,
    this.benchedPassing,
    this.benchedDribbling,
    this.benchedDefending,
    this.benchedPhysical,
    this.benchedAltPositions = const [],
    this.benchedNaturalPositions = const [],
    this.benchedChemistryBonuses = const [],
    this.benchHoldsStarter = false,
    this.benchedCaptain = false,
    this.benchedRedCarded = false,
    this.benchedCoached = false,
  });
  final String positionGroup;
  final String? spinResultClub;
  final String? chosenPlayerId;
  final String? chosenPlayerName;
  final int? chosenPlayerRating;
  final String? chosenPlayerPosition;
  final int? swappedSlotIndex;
  final String? benchedPlayerId;
  final String? benchedPlayerName;
  final int? benchedPlayerRating;
  final String? benchedPlayerPosition;
  final String? benchedImageUrl;
  final String? benchedClub;
  final String? benchedClubLogoUrl;
  final String? benchedPrimaryColor;
  final String? benchedSecondaryColor;
  final String? benchedTertiaryColor;
  final String? benchedKitPattern;
  final String? benchedCardStyle;
  final int? benchedKitNumber;
  final String? benchedNationality;
  final int? benchedPace;
  final int? benchedShooting;
  final int? benchedPassing;
  final int? benchedDribbling;
  final int? benchedDefending;
  final int? benchedPhysical;
  final List<String> benchedAltPositions;
  final List<String> benchedNaturalPositions;

  /// The bench card's own tiered chemistry challenges, used to show per-challenge
  /// achieved/remaining progress when the player inspects the bench card.
  final List<ChemistryBonus> benchedChemistryBonuses;

  /// True when the bench currently holds a swapped-out starter rather than the
  /// originally-chosen sub.
  final bool benchHoldsStarter;

  /// True when the card CURRENTLY on the bench (whichever one that is — see
  /// [benchHoldsStarter]) is captained by its owner. Mirrors [PitchSlot.
  /// isCaptain]'s identical per-card, follows-the-card-wherever-it-is
  /// semantics, so the badge stays consistent whether a captained card is
  /// currently starting or benched.
  final bool benchedCaptain;

  /// True when the card CURRENTLY on the bench was red-carded by an
  /// opponent (chemistry nullified). Mirrors [PitchSlot.isRedCarded].
  final bool benchedRedCarded;

  /// True when the card CURRENTLY on the bench was given an extra position by
  /// a Coach card. Mirrors [PitchSlot.isCoached].
  final bool benchedCoached;

  bool get isPicked => chosenPlayerId != null;
  bool get isSwapped => swappedSlotIndex != null;

  /// The card physically on the bench right now, built from the server's
  /// `benched*` fields (which the server populates with the current bench card —
  /// displaced starter or original sub). Null until the server snapshot arrives.
  CandidateCard? get benchCard {
    final id = benchedPlayerId;
    if (id == null) return null;
    return CandidateCard(
      cardId: id,
      playerName: benchedPlayerName ?? '',
      basePositionType: benchedPlayerPosition ?? '',
      rating: benchedPlayerRating ?? 0,
      imageUrl: benchedImageUrl,
      club: benchedClub,
      clubLogoUrl: benchedClubLogoUrl,
      primaryColor: benchedPrimaryColor,
      secondaryColor: benchedSecondaryColor,
      tertiaryColor: benchedTertiaryColor,
      kitPattern: benchedKitPattern,
      cardStyle: benchedCardStyle,
      kitNumber: benchedKitNumber,
      nationality: benchedNationality,
      pace: benchedPace ?? 0,
      shooting: benchedShooting ?? 0,
      passing: benchedPassing ?? 0,
      dribbling: benchedDribbling ?? 0,
      defending: benchedDefending ?? 0,
      physical: benchedPhysical ?? 0,
      altPositions: benchedAltPositions,
      naturalPositions: benchedNaturalPositions,
      chemistryBonuses: benchedChemistryBonuses,
    );
  }
}

@immutable
class UserSubstitutions {
  const UserSubstitutions({
    this.att,
    this.mid,
    this.def,
    this.extra,
    this.hasExtraBench = false,
    required this.isComplete,
    required this.lineupConfirmed,
  });
  final SubSlot? att;
  final SubSlot? mid;
  final SubSlot? def;

  /// Extra any-position bench sub, granted by the Extra Bench ability card.
  final SubSlot? extra;

  /// True when this player activated Extra Bench (gets the 4th sub slot).
  final bool hasExtraBench;
  final bool isComplete;
  final bool lineupConfirmed;

  int get pickedCount =>
      (att?.isPicked == true ? 1 : 0) +
      (mid?.isPicked == true ? 1 : 0) +
      (def?.isPicked == true ? 1 : 0) +
      (extra?.isPicked == true ? 1 : 0);
}

@immutable
class SubsPhase {
  const SubsPhase({required this.userSubs});
  final Map<String, UserSubstitutions> userSubs;
}

@immutable
class GameResult {
  const GameResult({required this.reason, required this.players});

  final String reason; // 'completed' | 'forfeit' | 'abandoned'
  final List<PlayerResult> players;

  PlayerResult? get firstPlace => players.where((p) => p.rank == 1).firstOrNull;
}

@immutable
class GameState {
  const GameState({
    required this.sessionId,
    required this.roomCode,
    required this.formationName,
    required this.players,
    required this.pitches,
    required this.baseTurnOrder,
    required this.currentRound,
    required this.totalRounds,
    required this.currentTurnOrder,
    required this.currentTurnIndex,
    required this.currentRoundSlotIndex,
    required this.turn,
    required this.status,
    required this.isFinished,
    this.hiddenDeckSize = 0,
    this.hiddenSlotsTaken = const [],
    this.hiddenSlots = const [],
    this.lastRoundLeftovers = const [],
    this.subsPhase,
    this.subsTimerSeconds,
    this.subsDeadlineAtMs,
    this.result,
    this.scoringPreview,
    this.abilityDraft,
    this.myAbility,
    this.abilityActivations = const [],
    this.abilityActivationResolved,
    this.abilityActivationRevealed = false,
    this.yellowPenalties = const {},
    this.subSwappedCardIds = const {},
  });

  final String sessionId;
  final String roomCode;
  final String formationName;
  final List<GamePlayer> players;
  final Map<String, PlayerPitch> pitches;
  final List<String> baseTurnOrder;
  final int currentRound;
  final int totalRounds;
  final List<String> currentTurnOrder;
  final int currentTurnIndex;
  final int?
  currentRoundSlotIndex; // shared slot for current round; null = first player has not chosen yet
  final GameTurn turn;
  // 'waiting' | 'ability_draft' | 'drafting' | 'bench_selection' |
  // 'ability_activation' | 'lineup_edit' | 'tournament' | 'finished'
  final String status;
  final bool isFinished;
  final SubsPhase? subsPhase;

  /// Total seconds allotted for the subs phase. Null = no limit.
  final int? subsTimerSeconds;

  /// Epoch ms when the subs phase auto-confirms. Null = no limit / not in subs.
  final int? subsDeadlineAtMs;

  /// Total number of face-down slots in the hidden deck for the active round.
  /// 0 when not in a hidden-pick phase. Used by all clients to render the slot grid.
  final int hiddenDeckSize;

  /// 0-based indices of hidden slots that have already been picked this round.
  final List<int> hiddenSlotsTaken;

  /// Per-slot metadata for the hidden_pick phase. Empty outside that phase.
  /// Card data is present only for slots this local player picked.
  final List<HiddenSlotInfo> hiddenSlots;

  /// Cards no one picked in the round that just ended — revealed to all players
  /// and shown until the next round wraps. Empty before any round ends.
  final List<CandidateCard> lastRoundLeftovers;
  final GameResult? result;

  /// Private per-player scoring preview sent only to the local player.
  /// Null until the local player has at least one card placed.
  final ScoringPreview? scoringPreview;

  /// Face-down ability draft state; non-null only during `ability_draft`.
  final AbilityDraftState? abilityDraft;

  /// The local player's own chosen ability (private). Null until they pick.
  final PlayerAbility? myAbility;

  /// Public log of activated abilities, announced to all players.
  final List<AbilityActivation> abilityActivations;

  /// During `ability_activation`: playerId → has resolved (used/discarded).
  final Map<String, bool>? abilityActivationResolved;

  /// Whether the server's deterministic reveal pass has run for the current
  /// (or most recently completed) ability-activation phase. Stays true for
  /// the rest of the game once set — unlike [abilityActivationResolved],
  /// this is never null/cleared when status moves past `ability_activation`,
  /// so a client can always tell "reveal already happened" (e.g. on a
  /// reconnect deep into the subs phase) without depending on `status`.
  final bool abilityActivationRevealed;

  /// playerId → yellow-card points docked from their final score (0 if none).
  final Map<String, int> yellowPenalties;

  /// Card ids swapped between squads by a Sub card — the swap badge follows
  /// these cards (e.g. onto the bench after a sub).
  final Set<String> subSwappedCardIds;

  GamePlayer? get currentPlayer =>
      players.where((p) => p.id == turn.activePlayerId).firstOrNull;
}
