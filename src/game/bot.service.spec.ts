import { BotService } from './bot.service';
import { GameSession } from './interfaces/game-session.interface';
import { DraftCard } from './interfaces/draft-card.interface';

/**
 * Covers the AI opponent's move selection (solo mode). BotService is pure —
 * it reads a session and returns a move — so these build minimal session
 * shapes rather than standing up a real game.
 */

const BOT = 'bot-1';
const HUMAN = 'human-1';

function card(id: string, pos: string, rating: number): DraftCard {
  return {
    cardId: id,
    playerName: `P-${id}`,
    basePositionType: pos as never,
    rating,
    pace: 50,
    shooting: 50,
    passing: 50,
    dribbling: 50,
    defending: 50,
    physical: 50,
    nationality: 'X',
    club: 'Y',
    altPositions: [],
    naturalPositions: [pos as never],
  } as DraftCard;
}

/** Minimal session carrying only the fields the bot actually reads. */
function session(over: Partial<GameSession>): GameSession {
  return {
    status: 'drafting',
    players: [
      { id: HUMAN, displayName: 'H', isHost: true, isConnected: true },
      { id: BOT, displayName: 'AI', isHost: false, isConnected: true, isBot: true },
    ],
    pitches: {},
    turn: {
      turnId: 't1',
      phase: 'selecting_card',
      activePlayerId: BOT,
      activeSlotIndex: null,
      candidates: [],
      turnStartedAt: null,
    },
    roundCandidates: [],
    orderedHiddenDeck: [],
    hiddenPicksTaken: new Set<number>(),
    hiddenPickReveal: null,
    abilityDraft: null,
    playerAbilities: {},
    subsPhase: null,
    tournament: null,
    isFinished: false,
    ...over,
  } as unknown as GameSession;
}

describe('BotService', () => {
  let bot: BotService;
  beforeEach(() => {
    bot = new BotService();
  });

  describe('turn ownership', () => {
    it('returns nothing when it is not the bot’s turn', () => {
      const s = session({
        turn: {
          turnId: 't1',
          phase: 'selecting_card',
          activePlayerId: HUMAN,
          activeSlotIndex: 0,
          candidates: [card('a', 'ST', 90)],
          turnStartedAt: null,
        } as never,
      });
      expect(bot.decide(s, BOT)).toBeNull();
    });

    it('returns nothing in a phase that needs no bot input', () => {
      expect(bot.decide(session({ status: 'finished' as never }), BOT)).toBeNull();
    });
  });

  describe('card selection', () => {
    it('prefers the highest-rated card that fits the slot', () => {
      const s = session({
        pitches: {
          [BOT]: {
            playerId: BOT,
            filledCount: 0,
            slots: [{ index: 0, label: 'ST', basePositionType: 'ST', card: null }],
          },
        } as never,
        turn: {
          turnId: 't1',
          phase: 'selecting_card',
          activePlayerId: BOT,
          activeSlotIndex: 0,
          // The 99 is a defender — a naive "best rating" pick would take it.
          candidates: [card('def', 'CB', 99), card('st-hi', 'ST', 84), card('st-lo', 'ST', 70)],
          turnStartedAt: null,
        } as never,
      });
      expect(bot.decide(s, BOT)).toEqual({
        kind: 'pick_card',
        turnId: 't1',
        cardId: 'st-hi',
      });
    });

    it('falls back to the best available card when nothing fits the slot', () => {
      // Refusing to pick would stall the round, and the engine permits an
      // out-of-position card (it simply scores nothing for that slot).
      const s = session({
        pitches: {
          [BOT]: {
            playerId: BOT,
            filledCount: 0,
            slots: [{ index: 0, label: 'GK', basePositionType: 'GK', card: null }],
          },
        } as never,
        turn: {
          turnId: 't1',
          phase: 'selecting_card',
          activePlayerId: BOT,
          activeSlotIndex: 0,
          candidates: [card('a', 'ST', 70), card('b', 'CB', 88)],
          turnStartedAt: null,
        } as never,
      });
      expect(bot.decide(s, BOT)).toEqual({
        kind: 'pick_card',
        turnId: 't1',
        cardId: 'b',
      });
    });
  });

  describe('slot selection', () => {
    it('only ever picks a slot it has not already filled', () => {
      const s = session({
        pitches: {
          [BOT]: {
            playerId: BOT,
            filledCount: 2,
            slots: [
              { index: 0, label: 'GK', basePositionType: 'GK', card: card('x', 'GK', 70) },
              { index: 1, label: 'CB', basePositionType: 'CB', card: null },
              { index: 2, label: 'ST', basePositionType: 'ST', card: card('y', 'ST', 70) },
            ],
          },
        } as never,
        turn: {
          turnId: 't1',
          phase: 'selecting_position',
          activePlayerId: BOT,
          activeSlotIndex: null,
          candidates: [],
          turnStartedAt: null,
        } as never,
      });
      // Slot 1 is the only empty one.
      expect(bot.decide(s, BOT)).toEqual({
        kind: 'pick_slot',
        turnId: 't1',
        slotIndex: 1,
      });
    });

    it('drafts back to front, taking the lowest empty slot', () => {
      // The picked slot becomes the round's position for EVERY player, so this
      // must be deterministic and sensible rather than random — formation
      // slots run GK(0) → defence → midfield → attack.
      const s = session({
        pitches: {
          [BOT]: {
            playerId: BOT,
            filledCount: 1,
            slots: [
              { index: 0, label: 'GK', basePositionType: 'GK', card: card('g', 'GK', 70) },
              { index: 1, label: 'LB', basePositionType: 'LB', card: null },
              { index: 5, label: 'CM', basePositionType: 'CM', card: null },
              { index: 10, label: 'ST', basePositionType: 'ST', card: null },
            ],
          },
        } as never,
        turn: {
          turnId: 't1',
          phase: 'selecting_position',
          activePlayerId: BOT,
          activeSlotIndex: null,
          candidates: [],
          turnStartedAt: null,
        } as never,
      });
      // GK is taken, so the left-back at index 1 is next — not 5 or 10.
      expect(bot.decide(s, BOT)).toEqual({
        kind: 'pick_slot',
        turnId: 't1',
        slotIndex: 1,
      });
    });
  });

  describe('hidden deck', () => {
    it('orders the leftover deck weakest-first', () => {
      const s = session({
        roundCandidates: [card('hi', 'ST', 90), card('lo', 'CB', 60), card('mid', 'CM', 75)],
        turn: {
          turnId: 't1',
          phase: 'first_player_order',
          activePlayerId: BOT,
          activeSlotIndex: null,
          candidates: [],
          turnStartedAt: null,
        } as never,
      });
      expect(bot.decide(s, BOT)).toEqual({
        kind: 'order_hidden_deck',
        turnId: 't1',
        orderedCardIds: ['lo', 'mid', 'hi'],
      });
    });

    it('never picks a hidden slot someone already took', () => {
      const s = session({
        orderedHiddenDeck: [card('a', 'ST', 80), card('b', 'CB', 80), card('c', 'CM', 80)],
        hiddenPicksTaken: new Set([0, 2]),
        turn: {
          turnId: 't1',
          phase: 'hidden_pick',
          activePlayerId: BOT,
          activeSlotIndex: null,
          candidates: [],
          turnStartedAt: null,
        } as never,
      });
      expect(bot.decide(s, BOT)).toEqual({
        kind: 'pick_hidden_slot',
        turnId: 't1',
        slotIndex: 1,
      });
    });

    it('confirms a reveal only when the bot was the picker', () => {
      const base = {
        turn: {
          turnId: 't1',
          phase: 'hidden_pick_reveal',
          activePlayerId: BOT,
          activeSlotIndex: null,
          candidates: [],
          turnStartedAt: null,
        } as never,
      };
      const mine = session({
        ...base,
        hiddenPickReveal: { pickerPlayerId: BOT, timeoutAt: 0 } as never,
      });
      expect(bot.decide(mine, BOT)).toEqual({
        kind: 'confirm_hidden_reveal',
        turnId: 't1',
      });

      const theirs = session({
        ...base,
        hiddenPickReveal: { pickerPlayerId: HUMAN, timeoutAt: 0 } as never,
      });
      expect(bot.decide(theirs, BOT)).toBeNull();
    });
  });

  describe('bench selection', () => {
    it('fills att, mid and def in turn, then stops', () => {
      const subs: Record<string, unknown> = {};
      const make = () =>
        session({
          status: 'bench_selection' as never,
          subsPhase: { userSubs: { [BOT]: subs } } as never,
        });

      expect(bot.decide(make(), BOT)).toEqual({ kind: 'fill_bench', group: 'att' });
      subs.att = { chosenPlayerId: 'p1' };
      expect(bot.decide(make(), BOT)).toEqual({ kind: 'fill_bench', group: 'mid' });
      subs.mid = { chosenPlayerId: 'p2' };
      expect(bot.decide(make(), BOT)).toEqual({ kind: 'fill_bench', group: 'def' });
      subs.def = { chosenPlayerId: 'p3' };
      expect(bot.decide(make(), BOT)).toBeNull();
    });

    it('takes the highest-rated player a spin offers', () => {
      expect(
        bot.chooseSubFromSpin([
          { id: 'a', name: 'A', rating: 71, position: 'ST' },
          { id: 'b', name: 'B', rating: 83, position: 'ST' },
          { id: 'c', name: 'C', rating: 66, position: 'ST' },
        ]),
      ).toBe('b');
    });

    it('reports no choice when a spin returns nobody', () => {
      expect(bot.chooseSubFromSpin([])).toBeNull();
    });
  });

  describe('ability activation', () => {
    it('discards captain when its own pitch has no filled slot to target', () => {
      const s = session({
        status: 'ability_activation' as never,
        playerAbilities: { [BOT]: { type: 'captain', status: 'pending' } } as never,
      });
      expect(bot.decide(s, BOT)).toEqual({ kind: 'discard_ability' });
    });

    it('does nothing once its ability is already resolved', () => {
      const s = session({
        status: 'ability_activation' as never,
        playerAbilities: { [BOT]: { type: 'captain', status: 'discarded' } } as never,
      });
      expect(bot.decide(s, BOT)).toBeNull();
    });

    it('captains its own highest-rated starting-XI card', () => {
      const s = session({
        status: 'ability_activation' as never,
        playerAbilities: { [BOT]: { type: 'captain', status: 'pending' } } as never,
        pitches: {
          [BOT]: {
            slots: [
              { index: 0, basePositionType: 'ST', card: card('c1', 'ST', 70) },
              { index: 1, basePositionType: 'CM', card: card('c2', 'CM', 88) },
              { index: 2, basePositionType: 'CB', card: null },
            ],
          },
        } as never,
      });
      expect(bot.decide(s, BOT)).toEqual({
        kind: 'activate_ability',
        payload: { ownSlotIndex: 1 },
      });
    });

    it('always activates Extra Bench — pure upside, no target to weigh', () => {
      const s = session({
        status: 'ability_activation' as never,
        playerAbilities: { [BOT]: { type: 'extra_bench', status: 'pending' } } as never,
      });
      expect(bot.decide(s, BOT)).toEqual({
        kind: 'activate_ability',
        payload: {},
      });
    });

    it('always activates Protection — pure upside, no target to weigh', () => {
      const s = session({
        status: 'ability_activation' as never,
        playerAbilities: { [BOT]: { type: 'protect', status: 'pending' } } as never,
      });
      expect(bot.decide(s, BOT)).toEqual({
        kind: 'activate_ability',
        payload: {},
      });
    });

    it('targets the highest-rated opposing card with Yellow Card', () => {
      const s = session({
        status: 'ability_activation' as never,
        playerAbilities: { [BOT]: { type: 'yellow', status: 'pending' } } as never,
        pitches: {
          [HUMAN]: {
            slots: [
              { index: 0, basePositionType: 'ST', card: card('h1', 'ST', 60) },
              { index: 1, basePositionType: 'GK', card: card('h2', 'GK', 91) },
            ],
          },
        } as never,
      });
      expect(bot.decide(s, BOT)).toEqual({
        kind: 'activate_ability',
        payload: { targetUserId: HUMAN },
      });
    });

    it('targets the highest-rated opposing card and slot with Red Card', () => {
      const s = session({
        status: 'ability_activation' as never,
        playerAbilities: { [BOT]: { type: 'red', status: 'pending' } } as never,
        pitches: {
          [HUMAN]: {
            slots: [
              { index: 0, basePositionType: 'ST', card: card('h1', 'ST', 60) },
              { index: 1, basePositionType: 'GK', card: card('h2', 'GK', 91) },
            ],
          },
        } as never,
      });
      expect(bot.decide(s, BOT)).toEqual({
        kind: 'activate_ability',
        payload: { targetUserId: HUMAN, targetSlotIndex: 1 },
      });
    });

    it('discards an attacking ability when no opponent pitch is visible yet', () => {
      const s = session({
        status: 'ability_activation' as never,
        playerAbilities: { [BOT]: { type: 'red', status: 'pending' } } as never,
      });
      expect(bot.decide(s, BOT)).toEqual({ kind: 'discard_ability' });
    });

    it('freezes a random opponent — genuinely blind, same as a hidden-deck pick', () => {
      const s = session({
        status: 'ability_activation' as never,
        playerAbilities: { [BOT]: { type: 'freeze', status: 'pending' } } as never,
        pitches: { [HUMAN]: { slots: [] } } as never,
      });
      expect(bot.decide(s, BOT)).toEqual({
        kind: 'activate_ability',
        payload: { targetUserId: HUMAN },
      });
    });

    it('finds a beneficial Sub swap against a same-position rival card', () => {
      const s = session({
        status: 'ability_activation' as never,
        playerAbilities: { [BOT]: { type: 'sub', status: 'pending' } } as never,
        pitches: {
          [BOT]: {
            slots: [{ index: 0, basePositionType: 'ST', card: card('mine', 'ST', 65) }],
          },
          [HUMAN]: {
            slots: [{ index: 2, basePositionType: 'ST', card: card('theirs', 'ST', 85) }],
          },
        } as never,
      });
      expect(bot.decide(s, BOT)).toEqual({
        kind: 'activate_ability',
        payload: { ownSlotIndex: 0, targetUserId: HUMAN, targetSlotIndex: 2 },
      });
    });

    it('discards Sub when no rival card at a matching position is actually better', () => {
      const s = session({
        status: 'ability_activation' as never,
        playerAbilities: { [BOT]: { type: 'sub', status: 'pending' } } as never,
        pitches: {
          [BOT]: {
            slots: [{ index: 0, basePositionType: 'ST', card: card('mine', 'ST', 90) }],
          },
          [HUMAN]: {
            slots: [{ index: 2, basePositionType: 'ST', card: card('theirs', 'ST', 50) }],
          },
        } as never,
      });
      expect(bot.decide(s, BOT)).toEqual({ kind: 'discard_ability' });
    });

    it('coaches its best card into a genuinely new, not-already-owned position', () => {
      const s = session({
        status: 'ability_activation' as never,
        playerAbilities: { [BOT]: { type: 'coach', status: 'pending' } } as never,
        coachedPositions: {},
        pitches: {
          [BOT]: {
            slots: [{ index: 0, basePositionType: 'CM', card: card('mine', 'CM', 80) }],
          },
        } as never,
      });
      const result = bot.decide(s, BOT);
      expect(result?.kind).toBe('activate_ability');
      if (result?.kind === 'activate_ability') {
        expect(result.payload.ownSlotIndex).toBe(0);
        expect(result.payload.coachedPosition).toBeDefined();
        expect(result.payload.coachedPosition).not.toBe('GK');
      }
    });

    it('never targets a goalkeeper with Coach', () => {
      const s = session({
        status: 'ability_activation' as never,
        playerAbilities: { [BOT]: { type: 'coach', status: 'pending' } } as never,
        coachedPositions: {},
        pitches: {
          [BOT]: {
            slots: [{ index: 0, basePositionType: 'GK', card: card('keeper', 'GK', 90) }],
          },
        } as never,
      });
      expect(bot.decide(s, BOT)).toEqual({ kind: 'discard_ability' });
    });
  });

  describe('lineup confirmation', () => {
    it('confirms once the bench is complete', () => {
      const s = session({
        status: 'lineup_edit' as never,
        subsPhase: {
          userSubs: { [BOT]: { isComplete: true, lineupConfirmed: false } },
        } as never,
      });
      expect(bot.decide(s, BOT)).toEqual({ kind: 'confirm_lineup' });
    });

    it('waits rather than confirming an incomplete bench', () => {
      // confirmLineup would reject this with SUBS_NOT_COMPLETE; returning a
      // move here would stall the driver on a guaranteed rejection.
      const s = session({
        status: 'lineup_edit' as never,
        subsPhase: {
          userSubs: { [BOT]: { isComplete: false, lineupConfirmed: false } },
        } as never,
      });
      expect(bot.decide(s, BOT)).toBeNull();
    });

    it('does not confirm twice', () => {
      const s = session({
        status: 'lineup_edit' as never,
        subsPhase: {
          userSubs: { [BOT]: { isComplete: true, lineupConfirmed: true } },
        } as never,
      });
      expect(bot.decide(s, BOT)).toBeNull();
    });
  });

  describe('ability draft', () => {
    it('picks only on its own turn, and only an unclaimed card', () => {
      const s = session({
        status: 'ability_draft' as never,
        abilityDraft: {
          pool: [
            { id: 0, type: 'captain', pickedBy: HUMAN },
            { id: 1, type: 'red', pickedBy: null },
          ],
          pickOrder: [HUMAN, BOT],
          currentPickIndex: 1,
        } as never,
      });
      expect(bot.decide(s, BOT)).toEqual({ kind: 'pick_ability', cardId: 1 });
    });

    it('waits while another player is picking', () => {
      const s = session({
        status: 'ability_draft' as never,
        abilityDraft: {
          pool: [{ id: 0, type: 'captain', pickedBy: null }],
          pickOrder: [HUMAN, BOT],
          currentPickIndex: 0,
        } as never,
      });
      expect(bot.decide(s, BOT)).toBeNull();
    });
  });

  describe('tournament', () => {
    it('readies up during a ready check, once', () => {
      const pending = session({
        status: 'tournament' as never,
        tournament: { phase: 'ready_check', readyPlayerIds: [] } as never,
      });
      expect(bot.decide(pending, BOT)).toEqual({ kind: 'tournament_ready' });

      const already = session({
        status: 'tournament' as never,
        tournament: { phase: 'ready_check', readyPlayerIds: [BOT] } as never,
      });
      expect(bot.decide(already, BOT)).toBeNull();
    });

    it('stays out of every other tournament phase', () => {
      const s = session({
        status: 'tournament' as never,
        tournament: { phase: 'simulating', readyPlayerIds: [] } as never,
      });
      expect(bot.decide(s, BOT)).toBeNull();
    });
  });
});
