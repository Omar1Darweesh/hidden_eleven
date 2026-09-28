import { Injectable } from '@nestjs/common';
import { GameSession, SubPositionGroup } from './interfaces/game-session.interface.js';
import { DraftCard } from './interfaces/draft-card.interface.js';
import { COACHABLE_POSITIONS } from './interfaces/ability.interface.js';

/**
 * One move a bot wants to make. Deliberately mirrors the gateway's
 * `@SubscribeMessage` surface one-for-one so `RoomsGateway._driveBots` can
 * dispatch straight into the same `GameService` methods a human's socket
 * message would reach — a bot takes exactly the same code paths as a player,
 * with no parallel engine to keep in sync.
 */
export type BotAction =
  | { kind: 'pick_ability'; cardId: number }
  | { kind: 'pick_slot'; turnId: string; slotIndex: number }
  | { kind: 'pick_card'; turnId: string; cardId: string }
  | { kind: 'order_hidden_deck'; turnId: string; orderedCardIds: string[] }
  | { kind: 'pick_hidden_slot'; turnId: string; slotIndex: number }
  | { kind: 'confirm_hidden_reveal'; turnId: string }
  | { kind: 'fill_bench'; group: SubPositionGroup }
  | { kind: 'discard_ability' }
  | {
      kind: 'activate_ability';
      payload: {
        ownSlotIndex?: number;
        targetUserId?: string;
        targetSlotIndex?: number;
        coachedPosition?: string;
        ownBenchGroup?: string;
      };
    }
  | { kind: 'confirm_lineup' }
  | { kind: 'tournament_ready' };

/**
 * Decides what a server-driven AI opponent does. Pure and synchronous: it
 * reads a session and returns the single next move, never mutating anything
 * and never touching sockets or timers — all of that stays in the gateway.
 * That split is what makes the AI unit-testable without standing up a
 * WebSocket server.
 *
 * Difficulty is deliberately modest. The goal is a solo opponent that plays a
 * complete, coherent game so one person can experience the whole loop
 * end-to-end; it is not trying to be a strong adversary, and it never peeks at
 * information a human in the same seat could not see (it reads only its own
 * pitch, the candidates offered to it on its own turn, and public state).
 */
@Injectable()
export class BotService {
  /**
   * The next move for `botId`, or null when it is not this bot's turn (or the
   * phase needs nothing from it). Safe to call on every state change.
   */
  decide(session: GameSession, botId: string): BotAction | null {
    switch (session.status) {
      case 'ability_draft':
        return this._decideAbilityDraft(session, botId);
      case 'drafting':
        return this._decideDraft(session, botId);
      case 'bench_selection':
        return this._decideBench(session, botId);
      case 'ability_activation':
        return this._decideActivation(session, botId);
      case 'lineup_edit':
        return this._decideLineup(session, botId);
      case 'tournament':
        return this._decideTournament(session, botId);
      default:
        return null;
    }
  }

  /**
   * Which player to take from a bench spin's offered list. Split out from
   * [decide] because the choice depends on `requestSubSpin`'s return value,
   * which only exists after the spin has actually been performed.
   */
  chooseSubFromSpin(
    players: { id: string; name: string; rating: number; position: string }[],
  ): string | null {
    if (players.length === 0) return null;
    return players.reduce((best, p) => (p.rating > best.rating ? p : best)).id;
  }

  // ── Phase handlers ────────────────────────────────────────────────────────

  private _decideAbilityDraft(
    session: GameSession,
    botId: string,
  ): BotAction | null {
    const ad = session.abilityDraft;
    if (!ad) return null;
    if (ad.pickOrder[ad.currentPickIndex] !== botId) return null;

    // Face-down by design — the bot has no more information than a human here,
    // so it takes an arbitrary unclaimed card rather than pretending to choose.
    const available = ad.pool.filter((c) => c.pickedBy === null);
    if (available.length === 0) return null;
    return {
      kind: 'pick_ability',
      cardId: available[Math.floor(Math.random() * available.length)].id,
    };
  }

  private _decideDraft(session: GameSession, botId: string): BotAction | null {
    const turn = session.turn;
    if (turn.activePlayerId !== botId) return null;

    switch (turn.phase) {
      case 'selecting_position': {
        // The chosen slot becomes the round's position for EVERY player (see
        // `currentRoundSlotIndex` / ROUND_SLOT_ALREADY_CHOSEN in GameService),
        // so this is not a private decision — picking at random forces the
        // human into an arbitrary position each round and makes the draft feel
        // broken. Formation slots are ordered GK → defence → midfield →
        // attack, so taking the lowest empty index builds the team back to
        // front, which is how a person would actually draft.
        const empty = session.pitches[botId]?.slots
          .filter((s) => s.card === null)
          .map((s) => s.index);
        if (!empty || empty.length === 0) return null;
        return {
          kind: 'pick_slot',
          turnId: turn.turnId,
          slotIndex: Math.min(...empty),
        };
      }

      case 'selecting_card': {
        const slotIndex = turn.activeSlotIndex;
        if (slotIndex === null) return null;
        const slot = session.pitches[botId]?.slots[slotIndex];
        const best = this._bestCardForSlot(
          turn.candidates,
          slot?.basePositionType,
        );
        if (!best) return null;
        return { kind: 'pick_card', turnId: turn.turnId, cardId: best.cardId };
      }

      case 'first_player_order': {
        // The bot has already taken its own card; what remains becomes the
        // face-down deck everyone else picks from blind. Ordering weakest-first
        // is a real (if simple) strategy: the earliest blind pickers get the
        // least valuable cards.
        const ordered = [...session.roundCandidates]
          .sort((a, b) => a.rating - b.rating)
          .map((c) => c.cardId);
        return {
          kind: 'order_hidden_deck',
          turnId: turn.turnId,
          orderedCardIds: ordered,
        };
      }

      case 'hidden_pick': {
        // Genuinely blind — every remaining slot is equally unknown, so any
        // available index is as good as another.
        const taken = session.hiddenPicksTaken;
        const available: number[] = [];
        for (let i = 0; i < session.orderedHiddenDeck.length; i++) {
          if (!taken.has(i)) available.push(i);
        }
        if (available.length === 0) return null;
        return {
          kind: 'pick_hidden_slot',
          turnId: turn.turnId,
          slotIndex: available[Math.floor(Math.random() * available.length)],
        };
      }

      case 'hidden_pick_reveal':
        // Only the picker may confirm; for a bot there is nothing to look at.
        if (session.hiddenPickReveal?.pickerPlayerId !== botId) return null;
        return { kind: 'confirm_hidden_reveal', turnId: turn.turnId };

      default:
        return null;
    }
  }

  private _decideBench(session: GameSession, botId: string): BotAction | null {
    const subs = session.subsPhase?.userSubs[botId];
    if (!subs) return null;
    // 'extra' is deliberately excluded: it belongs to lineup_edit and only
    // exists for an Extra Bench holder, and this bot always discards its
    // ability (see _decideActivation), so it can never hold one.
    for (const group of ['att', 'mid', 'def'] as const) {
      if (!subs[group]?.chosenPlayerId) return { kind: 'fill_bench', group };
    }
    return null;
  }

  /**
   * Actually uses the drafted ability when a sound target exists, rather than
   * always discarding. Every read here is information a human in the same
   * seat could see too: the bot's own pitch in full, and opponents' PITCH
   * cards — which are public the moment they're drafted (unlike the one
   * genuinely secret hidden-deck pick, which this bot never touches).
   * Falls back to discarding only when the ability truly has no reasonable
   * target (e.g. no beneficial Sub swap exists) rather than picking blindly
   * and producing a nonsensical board.
   */
  private _decideActivation(
    session: GameSession,
    botId: string,
  ): BotAction | null {
    const ability = session.playerAbilities[botId];
    if (!ability || ability.status !== 'pending') return null;

    const ownSlots = (session.pitches[botId]?.slots ?? []).filter(
      (s) => s.card != null,
    );
    const opponents = session.players.filter(
      (p) => p.id !== botId && session.pitches[p.id] != null,
    );

    switch (ability.type) {
      // Pure upside, no target to weigh — always worth using.
      case 'extra_bench':
      case 'protect':
        return { kind: 'activate_ability', payload: {} };

      case 'captain': {
        const best = this._bestSlot(ownSlots);
        if (!best) return { kind: 'discard_ability' };
        return {
          kind: 'activate_ability',
          payload: { ownSlotIndex: best.index },
        };
      }

      case 'coach': {
        for (const slot of [...ownSlots].sort(
          (a, b) => (b.card?.rating ?? 0) - (a.card?.rating ?? 0),
        )) {
          const card = slot.card!;
          if (card.basePositionType === 'GK') continue;
          const owned = this._cardPositionSet(card);
          const newPos = COACHABLE_POSITIONS.find(
            (p) =>
              !owned.has(p) && session.coachedPositions[card.cardId] == null,
          );
          if (newPos) {
            return {
              kind: 'activate_ability',
              payload: { ownSlotIndex: slot.index, coachedPosition: newPos },
            };
          }
        }
        return { kind: 'discard_ability' };
      }

      case 'yellow': {
        const target = this._bestOpponentTarget(session, opponents);
        if (!target) return { kind: 'discard_ability' };
        return {
          kind: 'activate_ability',
          payload: { targetUserId: target.userId },
        };
      }

      case 'red': {
        const target = this._bestOpponentTarget(session, opponents);
        if (!target) return { kind: 'discard_ability' };
        return {
          kind: 'activate_ability',
          payload: {
            targetUserId: target.userId,
            targetSlotIndex: target.slotIndex,
          },
        };
      }

      case 'freeze': {
        // Which opponent holds which ability is exactly as hidden from this
        // bot as it is from a human at this point — a genuinely blind pick,
        // same as the hidden-deck slot choice in the draft phase.
        if (opponents.length === 0) return { kind: 'discard_ability' };
        const pick =
          opponents[Math.floor(Math.random() * opponents.length)];
        return {
          kind: 'activate_ability',
          payload: { targetUserId: pick.id },
        };
      }

      case 'sub': {
        let best: {
          ownIndex: number;
          rivalUid: string;
          rivalIndex: number;
          gain: number;
        } | null = null;
        for (const ownSlot of ownSlots) {
          for (const opp of opponents) {
            const rivalSlots = (session.pitches[opp.id]?.slots ?? []).filter(
              (s) =>
                s.card != null &&
                s.basePositionType === ownSlot.basePositionType,
            );
            for (const rSlot of rivalSlots) {
              const gain = rSlot.card!.rating - ownSlot.card!.rating;
              if (gain > 0 && (!best || gain > best.gain)) {
                best = {
                  ownIndex: ownSlot.index,
                  rivalUid: opp.id,
                  rivalIndex: rSlot.index,
                  gain,
                };
              }
            }
          }
        }
        if (!best) return { kind: 'discard_ability' };
        return {
          kind: 'activate_ability',
          payload: {
            ownSlotIndex: best.ownIndex,
            targetUserId: best.rivalUid,
            targetSlotIndex: best.rivalIndex,
          },
        };
      }

      default:
        return { kind: 'discard_ability' };
    }
  }

  private _decideLineup(session: GameSession, botId: string): BotAction | null {
    const subs = session.subsPhase?.userSubs[botId];
    if (!subs || subs.lineupConfirmed) return null;
    if (!subs.isComplete) return null;
    // The drafted XI is already in position and the bench is filled, so there
    // is nothing worth rearranging — confirm as-is.
    return { kind: 'confirm_lineup' };
  }

  private _decideTournament(
    session: GameSession,
    botId: string,
  ): BotAction | null {
    const t = session.tournament;
    if (!t || t.phase !== 'ready_check') return null;
    if (t.readyPlayerIds.includes(botId)) return null;
    return { kind: 'tournament_ready' };
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /**
   * Highest-rated candidate that can actually play the slot, falling back to
   * the highest-rated card overall when nothing fits — the engine allows an
   * out-of-position pick (it just scores 0 for that slot), and refusing to
   * pick at all would stall the round.
   */
  private _bestCardForSlot(
    candidates: DraftCard[],
    slotPosition: string | undefined,
  ): DraftCard | null {
    if (candidates.length === 0) return null;
    const byRating = (a: DraftCard, b: DraftCard) => b.rating - a.rating;

    if (slotPosition) {
      const fits = candidates.filter(
        (c) =>
          c.basePositionType === slotPosition ||
          c.naturalPositions?.includes(slotPosition as never) ||
          c.altPositions?.includes(slotPosition as never),
      );
      if (fits.length > 0) return [...fits].sort(byRating)[0];
    }
    return [...candidates].sort(byRating)[0];
  }

  /** Highest-rated filled slot, or null if none are filled. */
  private _bestSlot(
    slots: { index: number; card: DraftCard | null }[],
  ): { index: number; card: DraftCard } | null {
    let best: { index: number; card: DraftCard } | null = null;
    for (const s of slots) {
      if (!s.card) continue;
      if (!best || s.card.rating > best.card.rating) {
        best = { index: s.index, card: s.card };
      }
    }
    return best;
  }

  /**
   * Highest-rated starting-XI card across every opponent's pitch — the
   * obvious real-world target for an attacking ability (Yellow/Red Card).
   */
  private _bestOpponentTarget(
    session: GameSession,
    opponents: { id: string }[],
  ): { userId: string; slotIndex: number } | null {
    let best: { userId: string; slotIndex: number; rating: number } | null =
      null;
    for (const opp of opponents) {
      const slots = session.pitches[opp.id]?.slots ?? [];
      for (const s of slots) {
        if (!s.card) continue;
        if (!best || s.card.rating > best.rating) {
          best = { userId: opp.id, slotIndex: s.index, rating: s.card.rating };
        }
      }
    }
    return best ? { userId: best.userId, slotIndex: best.slotIndex } : null;
  }

  /**
   * Mirrors `GameService.cardPositionSet` (kept in sync manually — both are
   * small and stable): the full set of positions a card can already play,
   * used to find a genuinely NEW position Coach could add.
   */
  private _cardPositionSet(card: DraftCard): Set<string> {
    const nat =
      card.naturalPositions && card.naturalPositions.length > 0
        ? card.naturalPositions
        : [card.basePositionType, ...(card.altPositions ?? [])];
    return new Set<string>(nat);
  }
}
