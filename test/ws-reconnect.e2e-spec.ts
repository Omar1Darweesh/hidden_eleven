import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import { AddressInfo } from 'net';
import WebSocket from 'ws';
import { AppModule } from './../src/app.module';
import { IdStampingWsAdapter } from './../src/ws-adapter';

type WsEnvelope = { event: string; data: Record<string, unknown> };

/**
 * Minimal real WebSocket client for e2e — mirrors the Flutter client's
 * `{ event, data }` envelope over raw `ws`.
 */
class TestWsClient {
  private ws!: WebSocket;
  readonly inbox: WsEnvelope[] = [];
  private resolveWait: ((msg: WsEnvelope) => void) | null = null;

  async connect(url: string): Promise<void> {
    this.ws = new WebSocket(url);
    await new Promise<void>((resolve, reject) => {
      this.ws.once('open', () => resolve());
      this.ws.once('error', reject);
    });
    this.ws.on('message', (raw) => {
      const msg = JSON.parse(raw.toString()) as WsEnvelope;
      this.inbox.push(msg);
      if (this.resolveWait) {
        const resolve = this.resolveWait;
        this.resolveWait = null;
        resolve(msg);
      }
    });
  }

  send(event: string, data: Record<string, unknown> = {}): void {
    this.ws.send(JSON.stringify({ event, data }));
  }

  async waitFor(
    predicate: (msg: WsEnvelope) => boolean,
    timeoutMs = 10_000,
  ): Promise<WsEnvelope> {
    const existing = this.inbox.find(predicate);
    if (existing) return existing;

    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const remaining = deadline - Date.now();
      const msg = await new Promise<WsEnvelope>((resolve, reject) => {
        const timer = setTimeout(
          () => reject(new Error('waitFor timeout')),
          remaining,
        );
        this.resolveWait = (m) => {
          clearTimeout(timer);
          resolve(m);
        };
      }).catch(() => null);
      if (!msg) break;
      if (predicate(msg)) return msg;
    }
    throw new Error(
      `Timed out waiting for WS event. Inbox: ${this.inbox
        .map((m) => m.event)
        .join(', ')}`,
    );
  }

  async waitForEvent(event: string, timeoutMs = 10_000): Promise<WsEnvelope> {
    return this.waitFor((m) => m.event === event, timeoutMs);
  }

  latestGameState(): WsEnvelope | undefined {
    return [...this.inbox].reverse().find((m) => m.event === 'game_state');
  }

  close(): void {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.close();
    }
  }
}

describe('WebSocket reconnect happy path (e2e)', () => {
  let app: INestApplication;
  let wsUrl: string;

  beforeAll(async () => {
    process.env.NODE_ENV = 'test';
    process.env.RECONNECT_TOKEN_SECRET = 'e2e-test-secret';

    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
      }),
    );
    app.useWebSocketAdapter(new IdStampingWsAdapter(app));
    await app.listen(0);
    const addr = app.getHttpServer().address() as AddressInfo;
    wsUrl = `ws://127.0.0.1:${addr.port}`;
  });

  afterAll(async () => {
    await app.close();
  });

  it('create → join → start → one pick → disconnect → check_presence reconnect', async () => {
    const host = new TestWsClient();
    const guest = new TestWsClient();
    await host.connect(wsUrl);
    await guest.connect(wsUrl);

    host.send('create_room', {
      displayName: 'Host',
      leagues: [],
      tournamentEnabled: false,
    });
    const hostRoom = await host.waitForEvent('room_update');
    const roomCode = hostRoom.data['code'] as string;
    const hostPlayerId = hostRoom.data['localPlayerId'] as string;
    expect(roomCode).toMatch(/^[A-Za-z]{6}$/);
    expect(hostPlayerId).toBeTruthy();

    guest.send('join_room', { roomCode, displayName: 'Guest' });
    const guestRoom = await guest.waitFor(
      (m) =>
        m.event === 'room_update' &&
        typeof m.data['localPlayerId'] === 'string' &&
        m.data['reconnectToken'] != null,
    );
    const guestPlayerId = guestRoom.data['localPlayerId'] as string;
    const guestToken = guestRoom.data['reconnectToken'] as string;
    expect(guestPlayerId).toBeTruthy();
    expect(guestToken).toBeTruthy();

    host.send('start_game');
    const hostStartState = await host.waitForEvent('game_state');
    await guest.waitForEvent('game_state');
    const sessionId = hostStartState.data['sessionId'] as string;
    expect(sessionId).toBeTruthy();

    await advancePastAbilityDraft(host, guest, hostPlayerId, guestPlayerId);
    await takeOneDraftPick(host, guest, hostPlayerId, guestPlayerId);

    const preDisconnectState = guest.latestGameState();
    expect(preDisconnectState).toBeTruthy();
    const preTurnId = (preDisconnectState!.data['turn'] as { turnId?: string })
      ?.turnId;
    const preStatus = preDisconnectState!.data['status'] as string;

    guest.close();
    await new Promise((r) => setTimeout(r, 200));

    const guest2 = new TestWsClient();
    await guest2.connect(wsUrl);
    guest2.send('check_presence', {
      playerId: guestPlayerId,
      roomCode,
      reconnectToken: guestToken,
    });

    const reconnectedRoom = await guest2.waitFor(
      (m) =>
        m.event === 'room_update' &&
        m.data['localPlayerId'] === guestPlayerId,
    );
    expect(reconnectedRoom.data['code']).toBe(roomCode);

    const reconnectedGame = await guest2.waitForEvent('game_state');
    expect(reconnectedGame.data['sessionId']).toBe(sessionId);
    expect(reconnectedGame.data['roomCode']).toBe(roomCode);
    expect(reconnectedGame.data['localPlayerId']).toBe(guestPlayerId);
    expect(reconnectedGame.data['status']).toBe(preStatus);
    if (preTurnId) {
      expect(
        (reconnectedGame.data['turn'] as { turnId?: string })?.turnId,
      ).toBe(preTurnId);
    }

    const attacker = new TestWsClient();
    await attacker.connect(wsUrl);
    attacker.send('check_presence', {
      playerId: guestPlayerId,
      roomCode,
      reconnectToken: 'not-a-valid-token',
    });
    const err = await attacker.waitForEvent('error');
    expect(err.data['code']).toBe('INVALID_TOKEN');

    host.close();
    guest2.close();
    attacker.close();
  }, 45_000);
});

async function advancePastAbilityDraft(
  host: TestWsClient,
  guest: TestWsClient,
  hostPlayerId: string,
  guestPlayerId: string,
): Promise<void> {
  for (let step = 0; step < 12; step++) {
    const hostState = host.latestGameState();
    const status = hostState?.data['status'] as string | undefined;
    if (!status || status === 'drafting') return;
    if (status === 'ability_activation') {
      host.send('discard_ability');
      guest.send('discard_ability');
      await Promise.race([
        host.waitForEvent('game_state').catch(() => undefined),
        guest.waitForEvent('game_state').catch(() => undefined),
      ]);
      continue;
    }
    if (status !== 'ability_draft') return;

    const draft = hostState?.data['abilityDraft'] as
      | {
          currentPickerId?: string;
          cards?: Array<{ id: number; pickedBy?: string | null }>;
        }
      | undefined;
    const active = draft?.currentPickerId;
    const cards = (draft?.cards ?? []).filter((c) => c.pickedBy == null);
    if (!active || cards.length === 0) {
      await new Promise((r) => setTimeout(r, 80));
      continue;
    }
    const picker =
      active === hostPlayerId
        ? host
        : active === guestPlayerId
          ? guest
          : null;
    if (!picker) return;
    picker.send('pick_ability', { cardId: cards[0].id });
    await picker.waitForEvent('game_state');
  }
}

async function takeOneDraftPick(
  host: TestWsClient,
  guest: TestWsClient,
  hostPlayerId: string,
  guestPlayerId: string,
): Promise<void> {
  for (let i = 0; i < 30; i++) {
    const state = host.latestGameState() ?? guest.latestGameState();
    const status = state?.data['status'] as string | undefined;
    if (status === 'drafting') break;
    if (status === 'ability_activation') {
      host.send('discard_ability');
      guest.send('discard_ability');
    }
    await new Promise((r) => setTimeout(r, 80));
  }

  const state = host.latestGameState() ?? guest.latestGameState();
  if (state?.data['status'] !== 'drafting') return;

  const turn = state.data['turn'] as {
    turnId: string;
    phase: string;
    activePlayerId: string;
  };
  if (turn.phase !== 'selecting_position') return;

  const actor =
    turn.activePlayerId === hostPlayerId
      ? host
      : turn.activePlayerId === guestPlayerId
        ? guest
        : host;
  actor.send('pick_slot', { turnId: turn.turnId, slotIndex: 0 });
  await actor.waitFor(
    (m) =>
      m.event === 'game_state' ||
      m.event === 'slot_candidates' ||
      m.event === 'error',
  );
}
