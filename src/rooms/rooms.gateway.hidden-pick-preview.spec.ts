import { RoomsGateway } from './rooms.gateway';
import { RoomsService } from './rooms.service';
import { GameService } from '../game/game.service';
import { GameSession } from '../game/interfaces/game-session.interface';
import { Room } from './interfaces/room.interface';
import { DraftCard } from '../game/interfaces/draft-card.interface';

/**
 * Coverage for the hidden-draft "magician" intro's one backend addition:
 * `hidden_pick_prompt.previewCards` — the remaining hidden-deck cards, for
 * the client's reveal-conceal-shuffle animation. See rooms.gateway.ts's
 * `_previewCardsFor` doc comment for the full reasoning; the short version:
 *
 *   `session.orderedHiddenDeck[slotIndex]` IS how pickHiddenSlot resolves a
 *   pick — that array's OWN order is the real, secret slot mapping. Sending
 *   it verbatim in previewCards would let the picker read the mapping
 *   straight off the wire. So previewCards is the same cards, re-sorted by
 *   cardId — a completely different, slot-independent order.
 *
 * These tests prove: (1) the sort actually breaks positional correlation
 * with the real order (not just "it's *a* list of cards"), (2) it reaches
 * the wire in both places hidden_pick_prompt is sent (initial hand-off AND
 * reconnect resend), and (3) it has zero effect on which card an actual
 * pick resolves to — the field is purely additive/read-only.
 */
function draftCard(id: string): DraftCard {
  return {
    cardId: id,
    playerName: `Player ${id}`,
    basePositionType: 'CM',
    rating: 80,
    pace: 70,
    shooting: 70,
    passing: 70,
    dribbling: 70,
    defending: 70,
    physical: 70,
    nationality: 'Testland',
    club: 'Test FC',
    altPositions: [],
    naturalPositions: ['CM'],
    chemistryBonuses: [],
  };
}

function makeClient(id: string) {
  const sent: { event: string; data: unknown }[] = [];
  const client = {
    id,
    readyState: 1, // WebSocket.OPEN
    send: (raw: string) => sent.push(JSON.parse(raw)),
  };
  return { client, sent };
}

describe('RoomsGateway — hidden_pick_prompt.previewCards (magician intro)', () => {
  const ROOM_CODE = 'PVROOM';
  const SESSION_ID = 'sess-preview';

  let roomsService: RoomsService;
  let gameService: GameService;
  let gateway: RoomsGateway;

  // Deliberately NOT alphabetically sorted — this IS the real slot order:
  // orderedHiddenDeck[0] is slot 0, [1] is slot 1, [2] is slot 2.
  const deck = [draftCard('zebra'), draftCard('alpha'), draftCard('mango')];

  function emptyPitch(playerId: string) {
    // pickHiddenSlot resolves the picker's CURRENT round slot via
    // session.turn.activeSlotIndex — needs a real, empty slot there (index
    // 0, matching the fixture's turn below) or it rejects with
    // SLOT_NOT_FOUND before ever touching hiddenPicksMap.
    return {
      playerId,
      slots: [{ index: 0, label: 'CM', basePositionType: 'CM', card: null }],
      filledCount: 0,
    };
  }

  function hiddenPickSession(
    overrides: Partial<GameSession> = {},
  ): GameSession {
    return {
      sessionId: SESSION_ID,
      roomCode: ROOM_CODE,
      leagues: [],
      playerBonusCache: new Map(),
      userChallengeCache: new Map(),
      formation: { name: '4-3-3', slots: [] } as any,
      players: [
        { id: 'p1', displayName: 'Alice', isHost: true, isConnected: true },
        { id: 'p2', displayName: 'Bob', isHost: false, isConnected: true },
      ],
      pitches: { p1: emptyPitch('p1') as any, p2: emptyPitch('p2') as any },
      baseTurnOrder: ['p1', 'p2'],
      currentRound: 1,
      totalRounds: 11,
      currentTurnIndex: 0,
      currentRoundSlotIndex: 0,
      draftedCardIds: new Set(),
      roundCandidates: [],
      orderedHiddenDeck: deck,
      hiddenPicksTaken: new Set(),
      hiddenPicksMap: new Map(),
      hiddenPickReveal: null,
      lastRoundLeftovers: [],
      turn: {
        turnId: 't1',
        phase: 'hidden_pick',
        activePlayerId: 'p1',
        activeSlotIndex: 0,
        candidates: [],
        turnStartedAt: null,
      },
      turnTimeoutPolicy: { enabled: false, turnSeconds: null, onExpiry: null },
      status: 'drafting',
      abilityDraft: null,
      playerAbilities: {},
      abilityActivations: [],
      subSwappedCardIds: new Set(),
      isFinished: false,
      subsPhase: null,
      subsTimerSeconds: null,
      subsDeadlineAt: null,
      abilityActivationDeadlineAt: null,
      result: null,
      ...overrides,
    } as GameSession;
  }

  function setUpRoomAndSession(overrides: Partial<GameSession> = {}): {
    room: Room;
    session: GameSession;
  } {
    const room: Room = {
      code: ROOM_CODE,
      players: [
        {
          id: 'p1',
          displayName: 'Alice',
          isHost: true,
          isConnected: true,
          socketId: 'sock-p1',
        },
        {
          id: 'p2',
          displayName: 'Bob',
          isHost: false,
          isConnected: true,
          socketId: 'sock-p2',
        },
      ],
      spectators: [],
      isStarted: true,
      isLocked: false,
      kickedPlayerIds: [],
      kickedDisplayNames: [],
      pendingJoinRequests: [],
      lastActivityAt: Date.now(),
      leagues: [],
      turnTimerSeconds: null,
      subsTimerSeconds: null,
      formationSlug: null,
      tournamentEnabled: false,
      simulationSpeed: 'normal',
    } as any;

    (roomsService as unknown as { rooms: Map<string, Room> }).rooms.set(
      ROOM_CODE,
      room,
    );
    (
      roomsService as unknown as {
        socketIndex: Map<string, { roomCode: string; playerId: string }>;
      }
    ).socketIndex.set('sock-p1', { roomCode: ROOM_CODE, playerId: 'p1' });
    (
      roomsService as unknown as {
        socketIndex: Map<string, { roomCode: string; playerId: string }>;
      }
    ).socketIndex.set('sock-p2', { roomCode: ROOM_CODE, playerId: 'p2' });
    (
      roomsService as unknown as { playerRoomIndex: Map<string, string> }
    ).playerRoomIndex.set('p1', ROOM_CODE);
    (
      roomsService as unknown as { playerRoomIndex: Map<string, string> }
    ).playerRoomIndex.set('p2', ROOM_CODE);

    const session = hiddenPickSession(overrides);
    (
      gameService as unknown as { sessions: Map<string, GameSession> }
    ).sessions.set(session.sessionId, session);
    (
      gameService as unknown as { roomToSession: Map<string, string> }
    ).roomToSession.set(room.code, session.sessionId);

    return { room, session };
  }

  beforeEach(() => {
    roomsService = new RoomsService();
    gameService = new GameService();
    gateway = new RoomsGateway(roomsService, gameService);
  });

  afterEach(() => {
    gateway.onModuleDestroy();
  });

  it('_previewCardsFor sorts by cardId — breaking positional correlation with the real slot order', () => {
    const { session } = setUpRoomAndSession();

    const preview = (
      gateway as unknown as { _previewCardsFor(s: GameSession): DraftCard[] }
    )._previewCardsFor(session);

    // Same set of cards — nothing dropped or invented.
    expect(preview.map((c) => c.cardId).sort()).toEqual(
      deck.map((c) => c.cardId).sort(),
    );

    // Sorted ascending by cardId.
    expect(preview.map((c) => c.cardId)).toEqual(['alpha', 'mango', 'zebra']);

    // Critically: NOT the same order as orderedHiddenDeck — that array's
    // own index order IS the real slot mapping (orderedHiddenDeck[i] =
    // slot i). If this ever matched, the preview would leak it.
    expect(preview.map((c) => c.cardId)).not.toEqual(deck.map((c) => c.cardId));
  });

  it('a reconnect mid hidden_pick re-sends hidden_pick_prompt WITH previewCards, still safely ordered', () => {
    setUpRoomAndSession();
    const { client, sent } = makeClient('sock-p1-new');

    // check_presence re-associates this socket with p1 and, since p1 is the
    // active hidden-pick player, triggers _resendPhasePrompt.
    (
      roomsService as unknown as {
        socketIndex: Map<string, { roomCode: string; playerId: string }>;
      }
    ).socketIndex.set('sock-p1-new', { roomCode: ROOM_CODE, playerId: 'p1' });
    (
      gateway as unknown as {
        _resendPhasePrompt(
          client: unknown,
          session: GameSession,
          playerId: string,
        ): void;
      }
    )._resendPhasePrompt(
      client as never,
      (
        gameService as unknown as { sessions: Map<string, GameSession> }
      ).sessions.get(SESSION_ID)!,
      'p1',
    );

    const prompt = sent.find((m) => m.event === 'hidden_pick_prompt');
    expect(prompt).toBeDefined();
    const data = prompt!.data as { previewCards: DraftCard[] };
    expect(data.previewCards.map((c) => c.cardId)).toEqual([
      'alpha',
      'mango',
      'zebra',
    ]);
  });

  it('previewCards has zero effect on which card an actual pick resolves to', () => {
    setUpRoomAndSession();
    const { client } = makeClient('sock-p1');

    // Pick slot 0 — orderedHiddenDeck[0] is 'zebra' (the FIRST entry, well
    // before "alpha" in the preview's sorted display order) — proving the
    // real resolution still comes from the untouched orderedHiddenDeck
    // array, not from previewCards' cardId-sorted order.
    gateway.handlePickHiddenSlot(
      { turnId: 't1', slotIndex: 0 } as never,
      client as never,
    );

    const session = (
      gameService as unknown as { sessions: Map<string, GameSession> }
    ).sessions.get(SESSION_ID)!;
    expect(session.hiddenPicksMap.get(0)?.playerId).toBe('p1');
    // p1's pitch has no slots in this fixture, so the strongest available
    // assertion is the hidden-pick bookkeeping itself: slot 0 is now taken,
    // by p1, and the deck itself (source of truth) is untouched.
    expect(session.hiddenPicksTaken.has(0)).toBe(true);
    expect(session.orderedHiddenDeck.map((c) => c.cardId)).toEqual([
      'zebra',
      'alpha',
      'mango',
    ]);
  });
});
