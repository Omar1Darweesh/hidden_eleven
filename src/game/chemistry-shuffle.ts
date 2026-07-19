/**
 * ChemistryShuffleService
 *
 * Assigns exactly 3 tiered chemistry challenges (easy/medium/hard) to every
 * player card in a room. Each challenge is derived from that player's own data
 * (league, club, nation, position group) — not random — so the constraints
 * always make sense for the player on the card.
 *
 *   easy   (+2): ≥2 teammates from the player's league
 *   medium (+4): ≥2 from the player's club (if well-represented) else ≥N nation
 *   hard   (+6): (≥X club OR ≥X nation) AND ≥Y in the player's position group
 *
 * Usage:
 *   const svc = new ChemistryShuffleService();
 *   const cache = svc.buildBonusCache(sessionId, leagues, playerPool, tierRewards);
 *   // cache.get('fc_209331') → [easyChallenge, mediumChallenge, hardChallenge]
 */

import { PlayerCardDefinition } from './data/player-pool.js';
import { ChemistryBonus, POSITION_GROUPS } from './data/league-bonus-pools.js';
import { CLUB_LEAGUE } from './scoring.js';
import { ScoringConfigValues } from './scoring-config.js';

type TierRewards = ScoringConfigValues['cardChemistry']['tierRewards'];

export type { ChemistryBonus };

// ── Helpers ───────────────────────────────────────────────────────────────────

function positionGroupOf(pos: string): 'DEF' | 'MID' | 'ATK' {
  if (POSITION_GROUPS.DEF.includes(pos)) return 'DEF';
  if (POSITION_GROUPS.MID.includes(pos)) return 'MID';
  return 'ATK';
}

function groupLabel(g: string): string {
  return g === 'DEF' ? 'Defenders' : g === 'MID' ? 'Midfielders' : 'Attackers';
}

interface PoolCounts {
  clubCounts: Map<string, number>;
  nationCounts: Map<string, number>;
}

/** Count how many pool players (within active leagues) share each club / nation. */
function buildCounts(leagues: string[], pool: PlayerCardDefinition[]): PoolCounts {
  const leagueSet = new Set(leagues);
  const filtered = leagueSet.size > 0
    ? pool.filter((p) => leagueSet.has((p as any).league ?? CLUB_LEAGUE[p.club] ?? ''))
    : pool;

  const clubCounts = new Map<string, number>();
  const nationCounts = new Map<string, number>();
  for (const p of filtered) {
    if (p.club) clubCounts.set(p.club, (clubCounts.get(p.club) ?? 0) + 1);
    if (p.nationality) {
      nationCounts.set(p.nationality, (nationCounts.get(p.nationality) ?? 0) + 1);
    }
  }
  return { clubCounts, nationCounts };
}

// ── Public service ────────────────────────────────────────────────────────────

export class ChemistryShuffleService {
  /**
   * Build a map of playerId → [easy, medium, hard] challenges for all players.
   * Call once per session and cache the result on the GameSession.
   *
   * `sessionId` is accepted for signature compatibility; challenges are now
   * deterministic from player data, so it is not used.
   */
  buildBonusCache(
    _sessionId: string,
    leagues: string[],
    pool: PlayerCardDefinition[],
    tierRewards: TierRewards,
  ): Map<string, ChemistryBonus[]> {
    const counts = buildCounts(leagues, pool);
    // With a single league selected, every player shares it, so a SAME_LEAGUE
    // easy bonus would be free points — use a meaningful basis instead.
    const singleLeague = leagues.length === 1;
    const cache = new Map<string, ChemistryBonus[]>();
    for (const player of pool) {
      cache.set(player.id, this._buildTiered(player, counts, singleLeague, tierRewards));
    }
    return cache;
  }

  /** Build the 3 tiered challenges for a single player from their own data. */
  private _buildTiered(
    player: PlayerCardDefinition,
    counts: PoolCounts,
    singleLeague: boolean,
    tierRewards: TierRewards,
  ): ChemistryBonus[] {
    const league = (player as any).league ?? CLUB_LEAGUE[player.club] ?? '';
    const club = player.club;
    const nation = player.nationality;
    const posGroup = positionGroupOf(player.positions[0]);
    const clubCount = club ? counts.clubCounts.get(club) ?? 0 : 0;
    const nationCount = nation ? counts.nationCounts.get(nation) ?? 0 : 0;

    const positionEasy = (): ChemistryBonus => ({
      tier: 'easy',
      reward: tierRewards.easy,
      type: 'POSITION_GROUP',
      params: { group: posGroup, count: 2 },
      label: `2+ ${groupLabel(posGroup)}`,
    });

    const out: ChemistryBonus[] = [];

    // ── EASY (+2): same league — but that's free in a single-league room, so
    //    fall back to a meaningful nation/club/position basis there. ──────────
    if (!singleLeague) {
      out.push({
        tier: 'easy',
        reward: tierRewards.easy,
        type: 'SAME_LEAGUE',
        params: { league, count: 2 },
        label: league ? `2+ ${league} players` : '2+ same-league players',
      });
    } else if (nation && nationCount >= 2) {
      out.push({
        tier: 'easy',
        reward: tierRewards.easy,
        type: 'SAME_NATION',
        params: { nation, count: 2 },
        label: `2+ ${nation} players`,
      });
    } else if (club && clubCount >= 2) {
      out.push({
        tier: 'easy',
        reward: tierRewards.easy,
        type: 'SAME_CLUB',
        params: { club, count: 2 },
        label: `2+ ${club} players`,
      });
    } else {
      out.push(positionEasy());
    }

    // ── MEDIUM (+4): same club if well-represented, else same nation ────────
    if (club && clubCount >= 3) {
      out.push({
        tier: 'medium',
        reward: tierRewards.medium,
        type: 'SAME_CLUB',
        params: { club, count: 2 },
        label: `2+ ${club} players`,
      });
    } else if (nation && nationCount >= 2) {
      const c = Math.min(3, nationCount);
      out.push({
        tier: 'medium',
        reward: tierRewards.medium,
        type: 'SAME_NATION',
        params: { nation, count: c },
        label: `${c}+ ${nation} players`,
      });
    } else if (club && clubCount >= 2) {
      out.push({
        tier: 'medium',
        reward: tierRewards.medium,
        type: 'SAME_CLUB',
        params: { club, count: 2 },
        label: `2+ ${club} players`,
      });
    } else {
      // No usable club/nation representation — fall back to position group.
      out.push({
        tier: 'medium',
        reward: tierRewards.medium,
        type: 'POSITION_GROUP',
        params: { group: posGroup, count: 3 },
        label: `3+ ${groupLabel(posGroup)}`,
      });
    }

    // ── HARD (+6): identity AND position group (always position-based) ──────
    const useClubForHard = !!club && clubCount >= 2 && clubCount >= nationCount;
    if (useClubForHard) {
      const c = Math.min(3, clubCount);
      out.push({
        tier: 'hard',
        reward: tierRewards.hard,
        type: 'CLUB_AND_POSITION',
        params: { club, clubCount: c, group: posGroup, groupCount: 2 },
        label: `${c}+ ${club} & 2+ ${groupLabel(posGroup)}`,
      });
    } else if (nation && nationCount >= 2) {
      const c = Math.min(3, nationCount);
      out.push({
        tier: 'hard',
        reward: tierRewards.hard,
        type: 'NATION_AND_POSITION',
        params: { nation, nationCount: c, group: posGroup, groupCount: 2 },
        label: `${c}+ ${nation} & 2+ ${groupLabel(posGroup)}`,
      });
    } else {
      // No identity representation at all — pure position-group hard.
      out.push({
        tier: 'hard',
        reward: tierRewards.hard,
        type: 'POSITION_GROUP',
        params: { group: posGroup, count: 4 },
        label: `4+ ${groupLabel(posGroup)}`,
      });
    }

    // Guard: the single-league easy bonus must not exactly duplicate the medium
    // one (which would double-reward the same condition). Downgrade to position.
    if (
      out[0].type === out[1].type &&
      JSON.stringify(out[0].params) === JSON.stringify(out[1].params)
    ) {
      out[0] = positionEasy();
    }

    return out;
  }
}
