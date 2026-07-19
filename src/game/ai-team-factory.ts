import { PlayerCardDefinition } from './data/player-pool';
import { Formation, SlotLabel } from './interfaces/formation.interface';
import { FrozenCard, ParticipantLineup } from './interfaces/game-session.interface';
import { CLUB_LEAGUE } from './scoring';

/** A real club selected to field an AI tournament participant. */
export interface AiClubSelection {
  club: string;
  league: string;
  clubLogoUrl?: string;
  /** That club's players from the room's league-filtered pool. */
  roster: PlayerCardDefinition[];
}

/**
 * Builds real-club AI tournament participants from the exact same player
 * pool and formation rules human drafting uses — no new dataset, no change
 * to the match simulation engine. AI participants are frozen onto a
 * `ParticipantLineup` at tournament start exactly like a human's confirmed
 * squad, so `runMatchSimulation` treats them identically.
 *
 * Selection is a one-time random pick at tournament start, same as the
 * bracket draw itself (`GameService.shuffle`, `Math.random`-backed) — it is
 * not seeded/replay-deterministic, and doesn't need to be: once picked, the
 * generated lineup is frozen and never regenerated for the rest of the
 * tournament.
 */
export class AiTeamFactory {
  /**
   * Picks a real club to represent one AI participant.
   *
   * - Restricted to `leagues` (the room's selected leagues) — the same
   *   league filter human drafting uses.
   * - Prefers a club nobody has already used (`usedClubIds`, e.g. clubs
   *   already appearing on a human's confirmed lineup, plus any AI clubs
   *   already picked earlier in this same call) so every participant feels
   *   like a distinct club; falls back to reusing a club only when every
   *   eligible club is already taken (small league pools).
   * - Prefers a club with an eligible player for every one of `formation`'s
   *   11 slots (so a full XI can always be filled), using the same strict
   *   position matching human drafting uses (`positions.includes(...)`).
   *   Falls back to the closest-fitting club (fewest unfillable slots) if
   *   nothing fully qualifies — `generateAiSquad` covers any remaining gap
   *   with the next-best available player rather than leaving a slot empty.
   *
   * Returns `null` only if the room's leagues have no players at all, in
   * which case the caller keeps the previous generic-placeholder behaviour.
   */
  static selectAiClub(
    pool: PlayerCardDefinition[],
    leagues: string[],
    usedClubIds: Set<string>,
    formation: Formation,
  ): AiClubSelection | null {
    const leagueSet = new Set(leagues);
    const byClub = new Map<string, PlayerCardDefinition[]>();
    for (const player of pool) {
      const league = player.league ?? CLUB_LEAGUE[player.club] ?? '';
      if (leagueSet.size > 0 && !leagueSet.has(league)) continue;
      const list = byClub.get(player.club);
      if (list) list.push(player);
      else byClub.set(player.club, [player]);
    }
    if (byClub.size === 0) return null;

    const missingSlotCount = (roster: PlayerCardDefinition[]): number => {
      const available = [...roster];
      let missing = 0;
      for (const slot of formation.slots) {
        const idx = available.findIndex((p) => p.positions.includes(slot.basePositionType));
        if (idx === -1) {
          missing++;
          continue;
        }
        available.splice(idx, 1); // consumed — one player can't fill two slots
      }
      return missing;
    };

    const rank = (entries: [string, PlayerCardDefinition[]][]) =>
      entries
        .map(([club, roster]) => ({ club, roster, missing: missingSlotCount(roster) }))
        .sort((a, b) => a.missing - b.missing);

    const unused = rank([...byClub.entries()].filter(([club]) => !usedClubIds.has(club)));
    const ranked = unused.length > 0 ? unused : rank([...byClub.entries()]);

    // Among the best-fitting clubs, pick randomly rather than always the
    // same one — keeps the draw varied across tournaments/rooms.
    const bestMissing = ranked[0].missing;
    const candidates = ranked.filter((c) => c.missing === bestMissing);
    const chosen = candidates[Math.floor(Math.random() * candidates.length)];

    return {
      club: chosen.club,
      league: chosen.roster[0]?.league ?? CLUB_LEAGUE[chosen.club] ?? '',
      clubLogoUrl: chosen.roster.find((p) => p.clubLogoUrl)?.clubLogoUrl,
      roster: chosen.roster,
    };
  }

  /**
   * Fills every slot of `formation` from `selection.roster`, mirroring how a
   * human lineup is frozen (`GameService._buildParticipantLineup`): the same
   * `FrozenCard` shape and the same overall-rating averaging, so AI squads
   * feed `runMatchSimulation` exactly like a human squad.
   *
   * Goalkeeper is filled first (keepers are scarcest in a thin roster), then
   * the rest of the formation in slot order; each slot takes the
   * highest-rated remaining eligible player, so the AI XI is the club's
   * strongest available combination rather than a random jumble. If a club's
   * data can't fill every slot (see `selectAiClub`), any leftover slot takes
   * the best remaining player regardless of position sooner than leave it
   * empty. The single highest-rated outfield starter wears the armband.
   *
   * AI cards carry no `chemistryBonuses`/`activeAbilityTypes` — those come
   * from human-only draft-time systems (user challenges, ability cards) that
   * AI participants never go through, so `chemistryScore` is reported as 0
   * rather than a fabricated number.
   */
  static generateAiSquad(selection: AiClubSelection, formation: Formation): ParticipantLineup {
    const available = [...selection.roster].sort((a, b) => b.rating - a.rating);
    const used = new Set<string>();
    const pitchCards: FrozenCard[] = [];

    const slotsGkFirst = [...formation.slots].sort((a, b) =>
      (a.basePositionType === 'GK' ? 0 : 1) - (b.basePositionType === 'GK' ? 0 : 1),
    );

    for (const slot of slotsGkFirst) {
      const onPosition = available.find(
        (p) => !used.has(p.id) && p.positions.includes(slot.basePositionType),
      );
      const fallback = onPosition ?? available.find((p) => !used.has(p.id));
      if (!fallback) continue; // squad genuinely too thin — slot stays unfilled
      used.add(fallback.id);
      pitchCards.push({
        cardId: fallback.id,
        playerName: fallback.name,
        rating: fallback.rating,
        basePositionType: slot.basePositionType,
        slotLabel: slot.label,
        nationality: fallback.nationality,
        club: fallback.club,
        league: fallback.league ?? selection.league,
        chemistryBonuses: [],
      });
    }

    // Restore formation slot order (the GK-first pass above was fill
    // priority only, not display order).
    const indexOfLabel = new Map(formation.slots.map((s) => [s.label, s.index]));
    pitchCards.sort((a, b) => (indexOfLabel.get(a.slotLabel) ?? 0) - (indexOfLabel.get(b.slotLabel) ?? 0));

    const benchCards: FrozenCard[] = available
      .filter((p) => !used.has(p.id))
      .slice(0, 4)
      .map((p) => ({
        cardId: p.id,
        playerName: p.name,
        rating: p.rating,
        basePositionType: p.positions[0],
        // Bench cards have no formation slot — mirrors the same unsafe-but-
        // established cast `_buildParticipantLineup` uses for human bench cards.
        slotLabel: p.positions[0] as unknown as SlotLabel,
        nationality: p.nationality,
        club: p.club,
        league: p.league ?? selection.league,
        chemistryBonuses: [],
      }));

    const overallRating =
      pitchCards.length > 0
        ? Math.round((pitchCards.reduce((acc, c) => acc + c.rating, 0) / pitchCards.length) * 10) / 10
        : 0;

    const captain = [...pitchCards]
      .filter((c) => c.basePositionType !== 'GK')
      .sort((a, b) => b.rating - a.rating)[0];

    return {
      formationSlug: formation.slug ?? formation.name,
      pitchCards,
      benchCards,
      overallRating,
      chemistryScore: 0,
      captainCardId: captain?.cardId ?? null,
      activeAbilityTypes: [],
    };
  }
}
