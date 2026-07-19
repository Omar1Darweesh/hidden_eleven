/**
 * UserChallengeShuffleService
 *
 * Assigns exactly 5 chemistry challenges to every game player at session start.
 * Challenges 1-4 are drawn from a pool validated against the room's player data.
 * Challenge 5 is always ALL_CHALLENGES_MET.
 *
 * The assignment is deterministic: same playerId + roomCode → same 5 challenges.
 */

import { PlayerCardDefinition } from './data/player-pool.js';
import { UserChallengeType, UserChemistryChallenge } from './data/user-challenge-pools.js';
import { CLUB_LEAGUE } from './scoring.js';

/** Points awarded per satisfied user challenge — admin-configurable (see scoring-config.ts). */
type RewardPerChallenge = number;

export type { UserChemistryChallenge };

// ── Seeded PRNG (mulberry32) ───────────────────────────────────────────────────

function hashString(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = (Math.imul(h, 0x01000193) >>> 0);
  }
  return h >>> 0;
}

function makePrng(seed: number) {
  let s = seed;
  return function rand(): number {
    s |= 0;
    s = (s + 0x6d2b79f5) | 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// ── Room-level aggregates ──────────────────────────────────────────────────────

interface RoomAggregates {
  // nation → count of players with that nation in the pool
  nations: Record<string, number>;
  // club → count of players with that club
  clubs: Record<string, number>;
  // league → count of players in that league
  leagues: Record<string, number>;
  // pairs where ≥2 players share BOTH nation AND club
  nationClubPairs: Array<{ nation: string; club: string; count: number }>;
  // the room's selected league names (could be subset of leagues in pool)
  selectedLeagues: string[];
}

function buildRoomAggregates(selectedLeagues: string[], pool: PlayerCardDefinition[]): RoomAggregates {
  const leagueSet = new Set(selectedLeagues);
  const filtered = leagueSet.size > 0
    ? pool.filter(p => {
        const l = (p as any).league ?? CLUB_LEAGUE[p.club] ?? '';
        return leagueSet.has(l);
      })
    : pool;

  const nations: Record<string, number> = {};
  const clubs: Record<string, number> = {};
  const leagues: Record<string, number> = {};
  const ncCount = new Map<string, Map<string, number>>(); // nation → club → count

  for (const p of filtered) {
    const n = p.nationality ?? '';
    const c = p.club ?? '';
    const l = (p as any).league ?? CLUB_LEAGUE[c] ?? '';
    if (n) nations[n] = (nations[n] ?? 0) + 1;
    if (c) clubs[c]   = (clubs[c]   ?? 0) + 1;
    if (l) leagues[l] = (leagues[l] ?? 0) + 1;

    if (n && c) {
      if (!ncCount.has(n)) ncCount.set(n, new Map());
      const m = ncCount.get(n)!;
      m.set(c, (m.get(c) ?? 0) + 1);
    }
  }

  const nationClubPairs: Array<{ nation: string; club: string; count: number }> = [];
  for (const [nation, clubMap] of ncCount.entries()) {
    for (const [club, count] of clubMap.entries()) {
      if (count >= 2) nationClubPairs.push({ nation, club, count });
    }
  }

  return { nations, clubs, leagues, nationClubPairs, selectedLeagues };
}

// ── Helpers ────────────────────────────────────────────────────────────────────

function pickOne<T>(arr: T[], rand: () => number): T | undefined {
  if (arr.length === 0) return undefined;
  return arr[Math.floor(rand() * arr.length)];
}

function challengeKey(c: UserChemistryChallenge): string {
  return `${c.type}:${JSON.stringify(c.params)}`;
}

// ── Challenge instantiation ────────────────────────────────────────────────────

function tryInstantiate(
  type: UserChallengeType,
  rand: () => number,
  agg: RoomAggregates,
  usedKeys: Set<string>,
  rewardPerChallenge: RewardPerChallenge,
): UserChemistryChallenge | null {
  for (let attempt = 0; attempt < 15; attempt++) {
    const c = _buildOne(type, rand, agg, rewardPerChallenge);
    if (!c) return null;
    const key = challengeKey(c);
    if (!usedKeys.has(key)) return c;
  }
  return null;
}

function _buildOne(
  type: UserChallengeType,
  rand: () => number,
  agg: RoomAggregates,
  rewardPerChallenge: RewardPerChallenge,
): UserChemistryChallenge | null {
  switch (type) {
    case 'NATION_COUNT': {
      const count = rand() < 0.5 ? 2 : 3;
      // Only nations with enough players in the pool
      const valid = Object.entries(agg.nations).filter(([, c]) => c >= count).map(([n]) => n);
      const nation = pickOne(valid, rand);
      if (!nation) return null;
      return {
        type, reward: rewardPerChallenge,
        params: { nation, count },
        label: `≥${count} ${nation} players`,
      };
    }

    case 'TWO_NATIONS_COMBO': {
      const count = 2;
      const valid = Object.entries(agg.nations).filter(([, c]) => c >= count).map(([n]) => n);
      if (valid.length < 2) return null;
      const n1 = pickOne(valid, rand)!;
      const rest = valid.filter(n => n !== n1);
      const n2 = pickOne(rest, rand);
      if (!n2) return null;
      return {
        type, reward: rewardPerChallenge,
        params: { nation1: n1, nation2: n2, count },
        label: `≥${count} ${n1} + ≥${count} ${n2}`,
      };
    }

    case 'CLUB_COUNT': {
      const count = rand() < 0.5 ? 2 : 3;
      const valid = Object.entries(agg.clubs).filter(([, c]) => c >= count).map(([c]) => c);
      const club = pickOne(valid, rand);
      if (!club) return null;
      return {
        type, reward: rewardPerChallenge,
        params: { club, count },
        label: `≥${count} ${club} players`,
      };
    }

    case 'TWO_CLUBS_COMBO': {
      const valid = Object.entries(agg.clubs).filter(([, c]) => c >= 2).map(([c]) => c);
      if (valid.length < 2) return null;
      const c1 = pickOne(valid, rand)!;
      const rest = valid.filter(c => c !== c1);
      const c2 = pickOne(rest, rand);
      if (!c2) return null;
      return {
        type, reward: rewardPerChallenge,
        params: { club1: c1, club2: c2 },
        label: `≥1 ${c1} + ≥1 ${c2}`,
      };
    }

    case 'LEAGUE_COUNT': {
      const count = rand() < 0.5 ? 3 : 4;
      const valid = Object.entries(agg.leagues).filter(([, c]) => c >= count).map(([l]) => l);
      const league = pickOne(valid, rand);
      if (!league) return null;
      return {
        type, reward: rewardPerChallenge,
        params: { league, count },
        label: `≥${count} ${league} players`,
      };
    }

    case 'TWO_LEAGUES_COMBO': {
      if (agg.selectedLeagues.length < 2) return null;
      const count = 2;
      const valid = agg.selectedLeagues.filter(l => (agg.leagues[l] ?? 0) >= count);
      if (valid.length < 2) return null;
      const l1 = pickOne(valid, rand)!;
      const rest = valid.filter(l => l !== l1);
      const l2 = pickOne(rest, rand);
      if (!l2) return null;
      return {
        type, reward: rewardPerChallenge,
        params: { league1: l1, league2: l2, count },
        label: `≥${count} ${l1} + ≥${count} ${l2}`,
      };
    }

    case 'NATION_AND_CLUB': {
      const count = 2;
      const valid = agg.nationClubPairs.filter(p => p.count >= count);
      const pair = pickOne(valid, rand);
      if (!pair) return null;
      return {
        type, reward: rewardPerChallenge,
        params: { nation: pair.nation, club: pair.club, count },
        label: `≥${count} ${pair.nation} ${pair.club} players`,
      };
    }

    case 'POSITION_GROUP': {
      const groups = ['DEF', 'MID', 'ATK'];
      const count = 3;
      const group = pickOne(groups, rand)!;
      const groupLabel = group === 'DEF' ? 'Defenders' : group === 'MID' ? 'Midfielders' : 'Attackers';
      return {
        type, reward: rewardPerChallenge,
        params: { group, count },
        label: `≥${count} ${groupLabel} in lineup`,
      };
    }

    default:
      return null;
  }
}

// ── Available type pool ────────────────────────────────────────────────────────

function buildTypePool(agg: RoomAggregates): UserChallengeType[] {
  const pool: UserChallengeType[] = [
    'NATION_COUNT', 'NATION_COUNT',
    'CLUB_COUNT', 'CLUB_COUNT',
    'POSITION_GROUP',
    'TWO_NATIONS_COMBO',
    'TWO_CLUBS_COMBO',
    'NATION_AND_CLUB',
  ];
  // A "≥N players from <league>" challenge is only meaningful when more than one
  // league is in play. With exactly one league selected EVERY player is from it,
  // so the challenge would be free points — skip it. (Empty selection = all
  // leagues, where it stays meaningful.)
  if (agg.selectedLeagues.length !== 1) {
    pool.push('LEAGUE_COUNT');
  }
  if (agg.selectedLeagues.length >= 2) {
    pool.push('TWO_LEAGUES_COMBO', 'TWO_LEAGUES_COMBO');
  }
  return pool;
}

// ── Public service ────────────────────────────────────────────────────────────

export class UserChallengeShuffleService {
  buildCache(
    playerIds: string[],
    roomCode: string,
    pool: PlayerCardDefinition[],
    selectedLeagues: string[],
    rewardPerChallenge: RewardPerChallenge,
  ): Map<string, UserChemistryChallenge[]> {
    const agg = buildRoomAggregates(selectedLeagues, pool);
    const typePool = buildTypePool(agg);
    const cache = new Map<string, UserChemistryChallenge[]>();

    for (const playerId of playerIds) {
      const seed = hashString(`${playerId}:${roomCode}`);
      const rand = makePrng(seed);
      cache.set(playerId, this._pick4plus1(rand, typePool, agg, rewardPerChallenge));
    }

    return cache;
  }

  private _pick4plus1(
    rand: () => number,
    typePool: UserChallengeType[],
    agg: RoomAggregates,
    rewardPerChallenge: RewardPerChallenge,
  ): UserChemistryChallenge[] {
    const result: UserChemistryChallenge[] = [];
    const usedKeys = new Set<string>();

    // Shuffle a copy of the type pool
    const shuffled = [...typePool].sort(() => rand() - 0.5);

    for (const type of shuffled) {
      if (result.length >= 4) break;
      const challenge = tryInstantiate(type, rand, agg, usedKeys, rewardPerChallenge);
      if (challenge) {
        result.push(challenge);
        usedKeys.add(challengeKey(challenge));
      }
    }

    // Fallback: pad with POSITION_GROUP if not enough challenges were generated
    while (result.length < 4) {
      const fallback = _buildOne('POSITION_GROUP', rand, agg, rewardPerChallenge);
      if (!fallback) break;
      const key = challengeKey(fallback);
      if (!usedKeys.has(key)) {
        result.push(fallback);
        usedKeys.add(key);
      }
    }

    // Challenge 5 is always ALL_CHALLENGES_MET
    result.push({
      type: 'ALL_CHALLENGES_MET',
      params: {},
      label: 'Satisfy all 4 other challenges',
      reward: rewardPerChallenge,
    });

    return result;
  }
}
