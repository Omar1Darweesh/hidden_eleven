import { Injectable } from '@nestjs/common';
import { GameSession, SubPositionGroup } from './interfaces/game-session.interface.js';
import { DraftCard } from './interfaces/draft-card.interface.js';

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

  private _decideActivation(
    session: GameSession,
    botId: string,
  ): BotAction | null {
    const ability = session.playerAbilities[botId];
    if (!ability || ability.status !== 'pending') return null;
    // Always discard. Every ability needs a target choice whose consequences
    // this bot is not equipped to weigh, and a wrong target is worse for the
    // human's experience than no ability at all — discarding is always legal
    // and never produces a nonsensical board.
    return { kind: 'discard_ability' };
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
}
