import { PitchSlot } from './interfaces/pitch.interface';
import { GameSession } from './interfaces/game-session.interface';
import { ScoreBreakdown, ScoreBreakdownLine } from './interfaces/game-result.interface';
import { ChemistryBonus, POSITION_GROUPS } from './data/league-bonus-pools.js';
import { UserChemistryChallenge } from './data/user-challenge-pools.js';
import { ScoringConfigValues, DEFAULT_SCORING_CONFIG_V1 } from './scoring-config.js';

type CardChemThresholds = ScoringConfigValues['cardChemistry']['thresholds'];

// ── Line groupings ─────────────────────────────────────────────────────────────

export const DEF_POSITIONS = new Set<string>(['GK', 'LB', 'CB', 'RB']);
export const MID_POSITIONS = new Set<string>(['CDM', 'CM', 'CAM', 'LM', 'RM']);
export const ATK_POSITIONS = new Set<string>(['LW', 'RW', 'CF', 'ST']);

// ── Club → League mapping ─────────────────────────────────────────────────────

export const CLUB_LEAGUE: Record<string, string> = {
  // Premier League
  'Liverpool FC':          'Premier League',
  'Manchester City':       'Premier League',
  'Manchester United':     'Premier League',
  'Chelsea':               'Premier League',
  'Arsenal':               'Premier League',
  'Tottenham Hotspur':     'Premier League',
  'Everton':               'Premier League',
  'Newcastle United':      'Premier League',
  'West Ham':              'Premier League',
  'Wolverhampton':         'Premier League',
  'Crystal Palace':        'Premier League',
  'Aston Villa':           'Premier League',
  'Nottingham Forest':     'Premier League',
  'Leicester City':        'Premier League',
  'Burnley':               'Premier League',
  // La Liga
  'Real Madrid':           'La Liga',
  'FC Barcelona':          'La Liga',
  'Atlético Madrid':       'La Liga',
  'Sevilla':               'La Liga',
  'Villarreal':            'La Liga',
  'Real Betis':            'La Liga',
  // Bundesliga
  'Bayern Munich':         'Bundesliga',
  'Borussia Dortmund':     'Bundesliga',
  'Bayer Leverkusen':      'Bundesliga',
  // Serie A
  'AC Milan':              'Serie A',
  'Inter Milan':           'Serie A',
  'Juventus':              'Serie A',
  'AS Roma':               'Serie A',
  'Atalanta':              'Serie A',
  'Fiorentina':            'Serie A',
  'Lazio':                 'Serie A',
  // Ligue 1
  'Paris Saint-Germain':   'Ligue 1',
  'Olympique Lyonnais':    'Ligue 1',
  'LOSC Lille':            'Ligue 1',
  // Eredivisie
  'PSV Eindhoven':         'Eredivisie',
  'Ajax':                  'Eredivisie',
  // Süper Lig
  'Galatasaray':           'Süper Lig',
  'Fenerbahçe':            'Süper Lig',
  // Others
  'Benfica':               'Primeira Liga',
  'Inter Miami':           'MLS',
  'La Galaxy':             'MLS',
  'LA Galaxy':             'MLS',
  'Toronto FC':            'MLS',
  'Al-Nassr':              'Saudi Pro League',
};

// ── Internal helpers ───────────────────────────────────────────────────────────

/**
 * True if the card occupying `slot` can legally play that slot's position
 * (primary or alternate). Out-of-position players — only possible when the subs
 * timer expires before they were fixed — are penalised during scoring.
 */
export function cardFitsSlot(slot: PitchSlot): boolean {
  const card = slot.card;
  if (!card) return false;
  const nat = (card.naturalPositions && card.naturalPositions.length > 0)
    ? card.naturalPositions
    : [card.basePositionType, ...(card.altPositions ?? [])];
  return nat.includes(slot.basePositionType);
}

/**
 * Returns a copy of `slots` where every out-of-position card is treated as
 * empty. Used for chemistry scoring so misplaced players earn nothing and don't
 * prop up teammates' bonuses.
 */
export function fittedScoringSlots(slots: PitchSlot[]): PitchSlot[] {
  return slots.map(s => (s.card && cardFitsSlot(s) ? s : { ...s, card: null }));
}

function lineAvg(slots: PitchSlot[], positions: Set<string>): number {
  const line = slots.filter(s => s.card !== null && positions.has(s.basePositionType));
  if (line.length === 0) return 0;
  // Out-of-position players stay in the denominator but contribute 0, dragging
  // the line average down as a timeout penalty.
  const sum = line.reduce((acc, s) => acc + (cardFitsSlot(s) ? s.card!.rating : 0), 0);
  return Math.round(sum / line.length);
}

function getCardLeague(slot: PitchSlot): string | undefined {
  const card = slot.card!;
  return (card as any).league ?? CLUB_LEAGUE[card.club ?? ''];
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

// ── Level 1: User challenge evaluation ───────────────────────────────────────

export interface ChallengeConditionProgress {
  label: string;
  current: number;
  required: number;
  satisfied: boolean;
}

export interface ChallengeProgress {
  satisfied: boolean;
  current: number;
  required: number;
  /** Set only for TWO_* combo types — one entry per sub-condition. */
  conditions?: ChallengeConditionProgress[];
}

export function evaluateUserChallengeWithProgress(
  challenge: UserChemistryChallenge,
  slots: PitchSlot[],
  othersSatisfied?: boolean[],
): ChallengeProgress {
  const filled = slots.filter(s => s.card !== null);
  const p = challenge.params;

  switch (challenge.type) {
    case 'NATION_COUNT': {
      const nation = p['nation'] as string;
      const required = (p['count'] as number) ?? 2;
      const current = Math.min(filled.filter(s => s.card!.nationality === nation).length, required);
      return { satisfied: current >= required, current, required };
    }
    case 'TWO_NATIONS_COMBO': {
      const n1 = p['nation1'] as string;
      const n2 = p['nation2'] as string;
      const required = (p['count'] as number) ?? 2;
      const c1 = Math.min(filled.filter(s => s.card!.nationality === n1).length, required);
      const c2 = Math.min(filled.filter(s => s.card!.nationality === n2).length, required);
      const conditions: ChallengeConditionProgress[] = [
        { label: n1, current: c1, required, satisfied: c1 >= required },
        { label: n2, current: c2, required, satisfied: c2 >= required },
      ];
      return { satisfied: c1 >= required && c2 >= required, current: c1 + c2, required: required * 2, conditions };
    }
    case 'CLUB_COUNT': {
      const club = p['club'] as string;
      const required = (p['count'] as number) ?? 2;
      const current = Math.min(filled.filter(s => s.card!.club === club).length, required);
      return { satisfied: current >= required, current, required };
    }
    case 'TWO_CLUBS_COMBO': {
      const c1label = p['club1'] as string;
      const c2label = p['club2'] as string;
      const c1 = Math.min(filled.filter(s => s.card!.club === c1label).length, 1);
      const c2 = Math.min(filled.filter(s => s.card!.club === c2label).length, 1);
      const conditions: ChallengeConditionProgress[] = [
        { label: c1label, current: c1, required: 1, satisfied: c1 >= 1 },
        { label: c2label, current: c2, required: 1, satisfied: c2 >= 1 },
      ];
      return { satisfied: c1 >= 1 && c2 >= 1, current: c1 + c2, required: 2, conditions };
    }
    case 'LEAGUE_COUNT': {
      const league = p['league'] as string;
      const required = (p['count'] as number) ?? 3;
      const current = Math.min(filled.filter(s => getCardLeague(s) === league).length, required);
      return { satisfied: current >= required, current, required };
    }
    case 'TWO_LEAGUES_COMBO': {
      const l1 = p['league1'] as string;
      const l2 = p['league2'] as string;
      const required = (p['count'] as number) ?? 2;
      const c1 = Math.min(filled.filter(s => getCardLeague(s) === l1).length, required);
      const c2 = Math.min(filled.filter(s => getCardLeague(s) === l2).length, required);
      const conditions: ChallengeConditionProgress[] = [
        { label: l1, current: c1, required, satisfied: c1 >= required },
        { label: l2, current: c2, required, satisfied: c2 >= required },
      ];
      return { satisfied: c1 >= required && c2 >= required, current: c1 + c2, required: required * 2, conditions };
    }
    case 'NATION_AND_CLUB': {
      const nation = p['nation'] as string;
      const club = p['club'] as string;
      const required = (p['count'] as number) ?? 2;
      const current = Math.min(filled.filter(s => s.card!.nationality === nation && s.card!.club === club).length, required);
      return { satisfied: current >= required, current, required };
    }
    case 'POSITION_GROUP': {
      const group = p['group'] as string;
      const required = (p['count'] as number) ?? 3;
      const positions = POSITION_GROUPS[group] ?? [];
      const current = Math.min(filled.filter(s => positions.includes(s.basePositionType)).length, required);
      return { satisfied: current >= required, current, required };
    }
    case 'ALL_CHALLENGES_MET': {
      const satisfiedCount = othersSatisfied ? othersSatisfied.filter(Boolean).length : 0;
      const required = othersSatisfied ? othersSatisfied.length : 4;
      return { satisfied: satisfiedCount >= required, current: satisfiedCount, required };
    }
    default:
      return { satisfied: false, current: 0, required: 1 };
  }
}

/** Evaluate all 5 user challenges and return per-challenge progress + total bonus. */
export function evaluateUserChallenges(
  challenges: UserChemistryChallenge[],
  slots: PitchSlot[],
): { satisfied: boolean[]; total: number } {
  if (!challenges || challenges.length === 0) return { satisfied: [], total: 0 };
  const satisfied: boolean[] = challenges.map((c, i) => {
    if (i === 4) return false;
    return evaluateUserChallengeWithProgress(c, slots).satisfied;
  });
  if (challenges.length === 5 && challenges[4].type === 'ALL_CHALLENGES_MET') {
    satisfied[4] = satisfied.slice(0, 4).every(Boolean);
  }
  const total = challenges.reduce((sum, c, i) => sum + (satisfied[i] ? c.reward : 0), 0);
  return { satisfied, total };
}

/** Like evaluateUserChallenges but returns full progress objects for the preview payload. */
export function evaluateUserChallengesWithProgress(
  challenges: UserChemistryChallenge[],
  slots: PitchSlot[],
): { progress: (ChallengeProgress & { type: string; label: string; reward: number })[]; total: number } {
  if (!challenges || challenges.length === 0) return { progress: [], total: 0 };

  const progresses = challenges.map((c, i) => {
    if (i === 4) return { satisfied: false, current: 0, required: 4 };
    return evaluateUserChallengeWithProgress(c, slots);
  });

  // ALL_CHALLENGES_MET depends on others 0-3
  if (challenges.length === 5 && challenges[4].type === 'ALL_CHALLENGES_MET') {
    const othersSatisfied = progresses.slice(0, 4).map(p => p.satisfied);
    progresses[4] = evaluateUserChallengeWithProgress(challenges[4], slots, othersSatisfied);
  }

  const total = challenges.reduce((sum, c, i) => sum + (progresses[i].satisfied ? c.reward : 0), 0);
  const progress = challenges.map((c, i) => ({
    type: c.type,
    label: c.label,
    reward: c.reward,
    params: c.params,
    ...progresses[i],
  }));

  return { progress, total };
}

// ── Level 2: Card chemistry evaluation ───────────────────────────────────────

function countInGroup(filled: PitchSlot[], group: string): number {
  const positions = POSITION_GROUPS[group] ?? [];
  return filled.filter(s => positions.includes(s.basePositionType)).length;
}

export function evaluateCardBonus(
  bonus: ChemistryBonus,
  slots: PitchSlot[],
  thresholds: CardChemThresholds = DEFAULT_SCORING_CONFIG_V1.cardChemistry.thresholds,
): boolean {
  const filled = slots.filter(s => s.card !== null);
  const p = bonus.params;

  switch (bonus.type) {
    case 'SAME_CLUB': {
      const club = p['club'] as string;
      const count = (p['count'] as number) ?? thresholds.sameClubCount;
      return filled.filter(s => s.card!.club === club).length >= count;
    }
    case 'SAME_NATION': {
      const nation = p['nation'] as string;
      const count = (p['count'] as number) ?? thresholds.sameNationCount;
      return filled.filter(s => s.card!.nationality === nation).length >= count;
    }
    case 'SAME_LEAGUE': {
      const league = p['league'] as string;
      const count = (p['count'] as number) ?? thresholds.sameLeagueCount;
      return filled.filter(s => getCardLeague(s) === league).length >= count;
    }
    case 'POSITION_GROUP': {
      const group = p['group'] as string;
      const count = (p['count'] as number) ?? thresholds.positionGroupCount;
      return countInGroup(filled, group) >= count;
    }
    case 'CLUB_AND_POSITION': {
      const club = p['club'] as string;
      const clubCount = (p['clubCount'] as number) ?? thresholds.clubAndPositionClubCount;
      const group = p['group'] as string;
      const groupCount = (p['groupCount'] as number) ?? thresholds.clubAndPositionGroupCount;
      return filled.filter(s => s.card!.club === club).length >= clubCount
          && countInGroup(filled, group) >= groupCount;
    }
    case 'NATION_AND_POSITION': {
      const nation = p['nation'] as string;
      const nationCount = (p['nationCount'] as number) ?? thresholds.nationAndPositionNationCount;
      const group = p['group'] as string;
      const groupCount = (p['groupCount'] as number) ?? thresholds.nationAndPositionGroupCount;
      return filled.filter(s => s.card!.nationality === nation).length >= nationCount
          && countInGroup(filled, group) >= groupCount;
    }
    default:
      return false;
  }
}

/**
 * Sum of every satisfied per-card challenge reward across all placed cards.
 * Each card carries 3 tiered challenges (easy/medium/hard, reward values
 * admin-configurable); all three can be satisfied independently, so a single
 * card contributes 0..(easy+medium+hard).
 */
export function computeCardChemTotal(
  slots: PitchSlot[],
  bonusCache: Map<string, ChemistryBonus[]>,
  thresholds: CardChemThresholds = DEFAULT_SCORING_CONFIG_V1.cardChemistry.thresholds,
): number {
  let total = 0;
  for (const slot of slots) {
    if (!slot.card) continue;
    const bonuses = bonusCache.get(slot.card.cardId) ?? [];
    for (const b of bonuses) {
      if (evaluateCardBonus(b, slots, thresholds)) total += b.reward ?? 0;
    }
  }
  return total;
}

// ── Line-leader chemistry (competitive, cross-player) ─────────────────────────

const LINE_POSITION_SETS = [DEF_POSITIONS, MID_POSITIONS, ATK_POSITIONS];

/**
 * The rating of a player's best IN-POSITION card in a given line, or -1 if they
 * have no in-position card there. Misplaced cards are ignored.
 */
function bestInLineRating(
  slots: PitchSlot[],
  positions: Set<string>,
  disabled?: Set<number>,
): number {
  let best = -1;
  for (const s of slots) {
    if (disabled?.has(s.index)) continue; // red-carded: gives no chemistry award
    if (s.card && positions.has(s.basePositionType) && cardFitsSlot(s)) {
      if (s.card.rating > best) best = s.card.rating;
    }
  }
  return best;
}

/**
 * "Line Leaders" chemistry is a competition BETWEEN players: for each line
 * (DEF incl. GK, MID, ATK), the player(s) who own the highest-rated in-position
 * card in that line — across the whole game — earn `bonusPerLine` (admin-
 * configurable). A player can win 0..3 lines. Ties share the award.
 *
 * Returns a map of playerId → bonus (0/1x/2x/3x bonusPerLine).
 */
export function computeLineLeaderAwards(
  session: GameSession,
  redDisabledByPlayer?: Record<string, Set<number>>,
  bonusPerLine: number = DEFAULT_SCORING_CONFIG_V1.lineLeader.bonusPerLine,
): Record<string, number> {
  const playerIds = session.players.map(p => p.id);
  const awards: Record<string, number> = {};
  for (const id of playerIds) awards[id] = 0;

  for (const positions of LINE_POSITION_SETS) {
    // Each player's best in-position card rating in this line.
    const perPlayerBest: Record<string, number> = {};
    let globalBest = -1;
    for (const id of playerIds) {
      const slots = session.pitches[id]?.slots ?? [];
      const best = bestInLineRating(slots, positions, redDisabledByPlayer?.[id]);
      perPlayerBest[id] = best;
      if (best > globalBest) globalBest = best;
    }
    if (globalBest <= 0) continue; // nobody has an in-position card in this line
    for (const id of playerIds) {
      if (perPlayerBest[id] === globalBest) awards[id] += bonusPerLine;
    }
  }

  return awards;
}

// ── Ability-card effects (Stage 4 scoring) ───────────────────────────────────

interface AbilityScoringEffects {
  /** casterId → the CARD id they captained (double that card's card-chem). */
  captainCardByPlayer: Record<string, string>;
  /** CARD ids red-carded (chemistry nullified wherever the card now sits). */
  redCardIds: Set<string>;
  /** playerId → total points docked by Yellow card(s) (e.g. 20, 40). */
  yellowPenaltyByPlayer: Record<string, number>;
}

function extractAbilityEffects(
  session: GameSession,
  yellowPenalty: number = DEFAULT_SCORING_CONFIG_V1.abilityEffects.yellowPenalty,
): AbilityScoringEffects {
  const captainCardByPlayer: Record<string, string> = {};
  const redCardIds = new Set<string>();
  const yellowPenaltyByPlayer: Record<string, number> = {};

  // Card/red effects are keyed on the CARD id (recorded at activation), so they
  // follow the player even if the lineup is rearranged in the subs phase.
  for (const [pid, ab] of Object.entries(session.playerAbilities ?? {})) {
    if (ab.status !== 'used') continue;
    if (ab.type === 'captain' && ab.targetPlayerId) {
      captainCardByPlayer[pid] = ab.targetPlayerId;
    } else if (ab.type === 'red' && ab.targetPlayerId) {
      redCardIds.add(ab.targetPlayerId);
    } else if (ab.type === 'yellow' && ab.targetUserId != null) {
      yellowPenaltyByPlayer[ab.targetUserId] =
        (yellowPenaltyByPlayer[ab.targetUserId] ?? 0) + yellowPenalty;
    }
  }
  return { captainCardByPlayer, redCardIds, yellowPenaltyByPlayer };
}

/** Slot indices on a pitch whose card was red-carded (by card id). */
function redDisabledIndices(slots: PitchSlot[], redCardIds: Set<string>): Set<number> {
  const out = new Set<number>();
  for (const s of slots) {
    if (s.card && redCardIds.has(s.card.cardId)) out.add(s.index);
  }
  return out;
}

/** Copy of slots with red-disabled cards removed (for chemistry-only passes). */
function withChemDisabled(slots: PitchSlot[], disabled?: Set<number>): PitchSlot[] {
  if (!disabled || disabled.size === 0) return slots;
  return slots.map(s => (disabled.has(s.index) ? { ...s, card: null } : s));
}

/**
 * Card-chem total plus the bonus contributed by a Captain card. The captained
 * slot's earned chemistry is counted `captainMultiplier` times in total; e.g.
 * the default multiplier of 2 "doubles" it (one extra copy, captainBonus ==
 * earned). A multiplier of 3 would count it three times (captainBonus ==
 * earned * 2), and so on.
 */
function computeCardChemWithCaptain(
  slots: PitchSlot[],
  bonusCache: Map<string, ChemistryBonus[]>,
  captainSlotIndex?: number,
  thresholds: CardChemThresholds = DEFAULT_SCORING_CONFIG_V1.cardChemistry.thresholds,
  captainMultiplier: number = DEFAULT_SCORING_CONFIG_V1.abilityEffects.captainMultiplier,
): { total: number; captainBonus: number } {
  let total = 0;
  let captainBonus = 0;
  for (const slot of slots) {
    if (!slot.card) continue;
    const bonuses = bonusCache.get(slot.card.cardId) ?? [];
    let earned = 0;
    for (const b of bonuses) {
      if (evaluateCardBonus(b, slots, thresholds)) earned += b.reward ?? 0;
    }
    total += earned;
    if (captainSlotIndex != null && slot.index === captainSlotIndex) {
      captainBonus = earned * (captainMultiplier - 1);
    }
  }
  return { total, captainBonus };
}

// ── Empty breakdown ────────────────────────────────────────────────────────────

export function emptyBreakdown(): ScoreBreakdown {
  return {
    defAvg: 0, midAvg: 0, atkAvg: 0,
    linesTotal: 0,
    userChemTotal: 0,
    cardChemTotal: 0,
    lineLeaderBonus: 0,
    finalScore: 0,
    scoringConfigVersion: 0,
    lines: [],
  };
}

// ── Breakdown explanation lines ────────────────────────────────────────────────

/**
 * Itemized, human-readable explanation of a finalScore — built from the exact
 * same numbers already computed for the flat ScoreBreakdown scalars, so the
 * explanation can never drift from the math it explains. Not yet rendered by
 * any client UI (that's a later phase) — this only populates the field.
 */
function buildBreakdownLines(input: {
  defAvg: number; midAvg: number; atkAvg: number;
  userChemTotal: number; cardChemTotal: number; lineLeaderBonus: number;
  captainBonus: number; yellowPenalty: number; redApplied: boolean;
}): ScoreBreakdownLine[] {
  const lines: ScoreBreakdownLine[] = [
    { key: 'def_avg', label: 'Defence average', amount: input.defAvg },
    { key: 'mid_avg', label: 'Midfield average', amount: input.midAvg },
    { key: 'atk_avg', label: 'Attack average', amount: input.atkAvg },
    { key: 'user_chem', label: 'Challenges completed', amount: input.userChemTotal },
    { key: 'card_chem', label: 'Card chemistry', amount: input.cardChemTotal },
  ];
  if (input.lineLeaderBonus > 0) {
    lines.push({ key: 'line_leader', label: 'Line Leader bonus', amount: input.lineLeaderBonus });
  }
  if (input.captainBonus > 0) {
    lines.push({ key: 'captain', label: 'Captain bonus', amount: input.captainBonus });
  }
  if (input.yellowPenalty > 0) {
    lines.push({ key: 'yellow_penalty', label: 'Yellow card penalty', amount: -input.yellowPenalty });
  }
  if (input.redApplied) {
    lines.push({ key: 'red_applied', label: 'Red card applied (chemistry nullified)', amount: 0 });
  }
  return lines;
}

// ── computeAllScores (game-end) ────────────────────────────────────────────────

export function computeAllScores(session: GameSession): Record<string, ScoreBreakdown> {
  const playerIds = session.players.map(p => p.id);

  // Admin-configured scoring values, snapshotted onto the session at
  // createSession() time (see game.service.ts) so a config change mid-game
  // never affects an in-progress session. Falls back to the v1 defaults for
  // sessions that predate this field (or hand-built test fixtures) — v1's
  // values equal today's previously-hardcoded constants exactly.
  const config = session.scoringConfig ?? DEFAULT_SCORING_CONFIG_V1;
  const scoringConfigVersion = session.scoringConfigVersion ?? 1;

  // Ability-card effects (captain / red / yellow) applied at scoring time.
  const effects = extractAbilityEffects(session, config.abilityEffects.yellowPenalty);

  // Red-disabled slot indices per player, derived from the final lineups so the
  // effect lands on whichever slot the red-carded card ended up in.
  const redDisabledByPlayer: Record<string, Set<number>> = {};
  for (const id of playerIds) {
    redDisabledByPlayer[id] = redDisabledIndices(
      session.pitches[id]?.slots ?? [],
      effects.redCardIds,
    );
  }

  // Line-leader is a competition between players — compute it once across all
  // lineups (excluding red-disabled cards), then fold each award in.
  const lineLeaderAwards = computeLineLeaderAwards(
    session,
    redDisabledByPlayer,
    config.lineLeader.bonusPerLine,
  );

  const result: Record<string, ScoreBreakdown> = {};
  for (const id of playerIds) {
    const pitch = session.pitches[id];
    if (!pitch) continue;
    const slots = pitch.slots;
    const redDisabled = redDisabledByPlayer[id];

    // Chemistry passes ignore red-carded cards entirely (their rating still
    // counts for the line averages below). Misplaced players also earn no card
    // chemistry but still count toward user challenges.
    const chemSlots = withChemDisabled(slots, redDisabled);
    const fitted = fittedScoringSlots(chemSlots);

    // Captain doubles the captained CARD's chem — find whichever slot now holds
    // it (it may have moved during subs).
    const capCardId = effects.captainCardByPlayer[id];
    const capSlotIndex = capCardId
      ? fitted.find((s) => s.card?.cardId === capCardId)?.index
      : undefined;

    const challenges = session.userChallengeCache?.get(id) ?? [];
    const { total: userChemTotal } = evaluateUserChallenges(challenges, chemSlots);
    const { total: cardChemTotal, captainBonus } = computeCardChemWithCaptain(
      fitted,
      session.playerBonusCache,
      capSlotIndex,
      config.cardChemistry.thresholds,
      config.abilityEffects.captainMultiplier,
    );

    // Line averages use the ORIGINAL slots — a red-carded player's rating still
    // counts; only their chemistry is nullified.
    const defAvg = lineAvg(slots, DEF_POSITIONS);
    const midAvg = lineAvg(slots, MID_POSITIONS);
    const atkAvg = lineAvg(slots, ATK_POSITIONS);
    const lineLeaderBonus = lineLeaderAwards[id] ?? 0;
    const yellowPenalty = effects.yellowPenaltyByPlayer[id] ?? 0;
    const redApplied = (redDisabled?.size ?? 0) > 0;

    // finalScore = lines + chemistry (user + card + captain + line leaders) − yellow
    const linesTotal = defAvg + midAvg + atkAvg;
    const finalScore = round2(
      linesTotal + userChemTotal + cardChemTotal + captainBonus + lineLeaderBonus - yellowPenalty,
    );

    result[id] = {
      defAvg, midAvg, atkAvg, linesTotal,
      userChemTotal, cardChemTotal, lineLeaderBonus,
      captainBonus,
      yellowPenalty,
      redApplied,
      finalScore,
      scoringConfigVersion,
      lines: buildBreakdownLines({
        defAvg, midAvg, atkAvg, userChemTotal, cardChemTotal, lineLeaderBonus,
        captainBonus, yellowPenalty, redApplied,
      }),
    };
  }

  return result;
}

// ── Live scoring preview (per-turn, single player) ─────────────────────────────

export interface LiveScoringPreview {
  defAvg: number;
  midAvg: number;
  atkAvg: number;
  linesTotal: number;
  userChallenges: ChallengeProgress[];
  userChemTotal: number;
  cardChemTotal: number;
  lineLeaderBonus: number;
  estimatedScore: number;
}

/**
 * Live per-turn preview for one player, reusing the exact same ability-effect
 * logic (captain doubling, red-card nullification, yellow penalty) as
 * `computeAllScores` — previously this preview ignored ability effects
 * entirely, which showed a live total that didn't move when a captain/red/
 * yellow card was activated even though the final score already accounted
 * for them. lineLeaderBonus stays 0 here on purpose: it's a competition
 * against the other players' lineups, only decided at the final whistle.
 */
export function computeLivePreview(
  session: GameSession,
  playerId: string,
): LiveScoringPreview | null {
  const pitch = session.pitches[playerId];
  if (!pitch) return null;

  // Same session-snapshotted config computeAllScores uses — see its comment.
  const config = session.scoringConfig ?? DEFAULT_SCORING_CONFIG_V1;

  const slots = pitch.slots;
  const effects = extractAbilityEffects(session, config.abilityEffects.yellowPenalty);
  const redDisabled = redDisabledIndices(slots, effects.redCardIds);
  const chemSlots = withChemDisabled(slots, redDisabled);
  const fitted = fittedScoringSlots(chemSlots);

  const capCardId = effects.captainCardByPlayer[playerId];
  const capSlotIndex = capCardId
    ? fitted.find((s) => s.card?.cardId === capCardId)?.index
    : undefined;

  const challenges = session.userChallengeCache?.get(playerId) ?? [];
  const { progress: userChallenges, total: userChemTotal } =
    evaluateUserChallengesWithProgress(challenges, chemSlots);
  const { total: cardChemTotal, captainBonus } = computeCardChemWithCaptain(
    fitted,
    session.playerBonusCache,
    capSlotIndex,
    config.cardChemistry.thresholds,
    config.abilityEffects.captainMultiplier,
  );

  const defAvg = lineAvg(slots, DEF_POSITIONS);
  const midAvg = lineAvg(slots, MID_POSITIONS);
  const atkAvg = lineAvg(slots, ATK_POSITIONS);
  const linesTotal = defAvg + midAvg + atkAvg;
  const yellowPenalty = effects.yellowPenaltyByPlayer[playerId] ?? 0;
  const lineLeaderBonus = 0;

  // Captain's doubled chem folds into cardChemTotal (it IS this card's chem,
  // counted twice) and yellow's penalty subtracts directly from the total —
  // both match how computeAllScores rolls them into finalScore, just without
  // adding new fields the client would need to know about.
  const estimatedScore = round2(
    linesTotal +
      userChemTotal +
      cardChemTotal +
      captainBonus +
      lineLeaderBonus -
      yellowPenalty,
  );

  return {
    defAvg,
    midAvg,
    atkAvg,
    linesTotal,
    userChallenges,
    userChemTotal,
    cardChemTotal: cardChemTotal + captainBonus,
    lineLeaderBonus,
    estimatedScore,
  };
}
