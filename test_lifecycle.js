/**
 * Hidden Eleven — WebSocket lifecycle verification
 * Run from hidden_eleven_server/ where 'ws' is installed.
 * Server must be running on :3000 before this script starts.
 */
const WebSocket = require('ws');

function makeClient(label) {
  return new Promise((resolve) => {
    const ws = new WebSocket('ws://localhost:3000');
    const events = [];
    ws.on('open', () => resolve({ ws, events, label }));
    ws.on('message', (raw) => {
      const msg = JSON.parse(raw.toString());
      events.push(msg);
    });
    ws.on('error', (e) => console.error(`[${label}] error`, e.message));
  });
}

function send(ws, event, data) {
  ws.send(JSON.stringify({ event, data: data || {} }));
}

function wait(ms) { return new Promise(r => setTimeout(r, ms)); }

// Use last() for non-ID queries (true last event of a type).
function last(events, eventName) {
  return [...events].reverse().find(e => e.event === eventName);
}

// Use first() to extract localPlayerId — personal event always arrives before
// the same-type broadcast. Broadcast version has no localPlayerId.
function first(events, eventName) {
  return events.find(e => e.event === eventName);
}

function pass(label, ok, note) {
  console.log(`  ${ok ? 'PASS' : 'FAIL'} ${label}${note ? ' – ' + note : ''}`);
  return ok;
}

async function run() {
  console.log('\n=== LIFECYCLE VERIFICATION ===\n');
  const results = [];

  // ── Setup: 2-player room, start game ─────────────────────────────────────
  const host   = await makeClient('HOST');
  const player = await makeClient('PLAYER');

  send(host.ws, 'create_room', { displayName: 'HostUser' });
  await wait(200);
  const hostRoom1  = last(host.events, 'room_update');
  const roomCode   = hostRoom1?.data?.code;
  const hostId     = hostRoom1?.data?.localPlayerId;

  send(player.ws, 'join_room', { roomCode, displayName: 'PlayerUser' });
  await wait(200);
  // first() — the personal room_update (with localPlayerId) always arrives before
  // the broadcast version (no localPlayerId).
  const playerRoom1 = first(player.events, 'room_update');
  const playerId    = playerRoom1?.data?.localPlayerId;

  send(host.ws, 'start_game');
  await wait(300);

  const hostGameEvt   = last(host.events,   'game_state');
  const playerGameEvt = last(player.events, 'game_state');

  // Case 1: game starts – game_state delivered with localPlayerId
  results.push(pass('Case 1 – game_state has localPlayerId for host',
    !!hostGameEvt?.data?.localPlayerId));
  results.push(pass('Case 1 – game_state has localPlayerId for player',
    !!playerGameEvt?.data?.localPlayerId));

  // ── Player exits game to home ─────────────────────────────────────────────
  const hostEventsBefore = host.events.length;
  send(player.ws, 'exit_game_to_home');
  await wait(300);

  const hostRoomAfterExit = last(host.events, 'room_update');
  const hostGameAfterExit = last(host.events, 'game_state');
  const pInRoom = hostRoomAfterExit?.data?.players?.find(p => p.id === playerId);
  const pInGame = hostGameAfterExit?.data?.players?.find(p => p.id === playerId);

  // Case 2: player leaves – server keeps player, marks disconnected
  results.push(pass('Case 2 – host receives room_update broadcast after player exit',
    !!hostRoomAfterExit && host.events.length > hostEventsBefore));
  results.push(pass('Case 2 – host receives game_state broadcast after player exit',
    !!hostGameAfterExit));
  results.push(pass('Case 2 – player still in room (not removed)',
    !!pInRoom, `isConnected=${pInRoom?.isConnected}`));
  results.push(pass('Case 10 – room_update shows player disconnected immediately',
    pInRoom && !pInRoom.isConnected));
  results.push(pass('Case 10 – game_state shows player disconnected immediately',
    pInGame && !pInGame.isConnected));

  // Case 4+5: disconnected player receives no further events (server cleared socketIndex)
  const playerBefore = player.events.length;
  send(host.ws, 'lock_room');
  await wait(200);
  send(host.ws, 'unlock_room');
  await wait(200);
  results.push(pass('Case 4+5 – exited player gets no further broadcasts',
    player.events.length === playerBefore,
    `before=${playerBefore} after=${player.events.length}`));

  // ── Reconnect ─────────────────────────────────────────────────────────────
  const reconnClient = await makeClient('PLAYER-REJOIN');
  send(reconnClient.ws, 'check_presence', { playerId, roomCode });
  await wait(300);

  // first() — personal room_update (with localPlayerId) arrives before broadcast.
  const reconnRoom    = first(reconnClient.events, 'room_update');
  const reconnGame    = first(reconnClient.events, 'game_state');
  const reconnLocalId = reconnGame?.data?.localPlayerId;
  const hostRoomAfterReconn = last(host.events, 'room_update');
  const pAfterReconn = hostRoomAfterReconn?.data?.players?.find(p => p.id === playerId);

  results.push(pass('Case 6 – reconnect delivers room_update', !!reconnRoom));
  results.push(pass('Case 6 – reconnect delivers game_state',  !!reconnGame));
  results.push(pass('Case 6 – game_state localPlayerId matches on reconnect',
    reconnLocalId === playerId, `got=${reconnLocalId}`));
  results.push(pass('Case 6 – host sees player reconnected',
    pAfterReconn?.isConnected === true));

  // ── Permanent leave ────────────────────────────────────────────────────────
  // In a 2-player game, permanent leave triggers forfeit-win for the remaining
  // player and immediately closes the room. No room_update is sent — only a
  // final game_state with isFinished=true. Check game_state only.
  send(reconnClient.ws, 'exit_game_to_home');
  await wait(200);
  const permClient = await makeClient('PLAYER-PERM');
  send(permClient.ws, 'leave_game_permanently', { playerId, roomCode });
  await wait(300);

  const hostGamePerm = last(host.events, 'game_state');
  const pGoneGame    = !hostGamePerm?.data?.players?.find(p => p.id === playerId);

  results.push(pass('Case 8 – permanent leave: game finished (forfeit)',
    hostGamePerm?.data?.isFinished === true));
  results.push(pass('Case 8 – permanent leave removes player from game_state',  pGoneGame));

  // ── Host permanent leave in a 2-player game → forfeit ────────────────────
  // In a 2-player game, host permanent leave triggers forfeit-win for the
  // remaining player. The room is closed immediately — no room_update, only
  // a final game_state. Host transfer only happens in 3+ player games where
  // the game continues after the host leaves. Verify forfeit path here.
  const h2 = await makeClient('HOST2');
  const p2 = await makeClient('PLAYER2');
  send(h2.ws, 'create_room', { displayName: 'HostTwo' });
  await wait(200);
  const h2Room  = last(h2.events, 'room_update');
  const h2Code  = h2Room?.data?.code;
  const h2Id    = h2Room?.data?.localPlayerId;
  send(p2.ws, 'join_room', { roomCode: h2Code, displayName: 'PlayerTwo' });
  await wait(200);
  // first() — personal join room_update with localPlayerId
  const p2Id = first(p2.events, 'room_update')?.data?.localPlayerId;
  send(h2.ws, 'start_game');
  await wait(200);
  send(h2.ws, 'exit_game_to_home');
  await wait(200);
  const h2Perm = await makeClient('HOST2-PERM');
  send(h2Perm.ws, 'leave_game_permanently', { playerId: h2Id, roomCode: h2Code });
  await wait(300);

  // 2-player game: host leaving ends game → p2 gets a final game_state (forfeit win).
  const p2FinalGame = last(p2.events, 'game_state');
  const p2Winner = p2FinalGame?.data?.result?.players?.find(p => p.rank === 1);

  results.push(pass('Case 9 – host perm leave: game finished (forfeit)',
    p2FinalGame?.data?.isFinished === true));
  results.push(pass('Case 9 – remaining player wins the forfeit',
    p2Winner?.playerId === p2Id, `winner=${p2Winner?.playerId} expected=${p2Id}`));

  // ── Forfeit: declareForfeitWin rank correctness ────────────────────────────
  // 2-player forfeit: only the winner appears in result (loser permanently left).
  const hf = await makeClient('FORFEIT-HOST');
  const pf = await makeClient('FORFEIT-PLAYER');
  send(hf.ws, 'create_room', { displayName: 'ForfeitHost' });
  await wait(150);
  const fCode = last(hf.events, 'room_update')?.data?.code;
  const hfId  = last(hf.events, 'room_update')?.data?.localPlayerId;
  send(pf.ws, 'join_room', { roomCode: fCode, displayName: 'ForfeitPlayer' });
  await wait(150);
  const pfId = first(pf.events, 'room_update')?.data?.localPlayerId;
  send(hf.ws, 'start_game');
  await wait(300);

  // Player leaves permanently — triggers forfeit win for host.
  send(pf.ws, 'exit_game_to_home');
  await wait(200);
  const pfPerm = await makeClient('FORFEIT-PERM');
  send(pfPerm.ws, 'leave_game_permanently', { playerId: pfId, roomCode: fCode });
  await wait(400);

  const hfFinalGame = last(hf.events, 'game_state');
  const forfeitResult = hfFinalGame?.data?.result;
  const winner = forfeitResult?.players?.find(p => p.rank === 1);

  results.push(pass('Forfeit – game marked finished', hfFinalGame?.data?.isFinished === true));
  results.push(pass('Forfeit – reason is forfeit', forfeitResult?.reason === 'forfeit'));
  results.push(pass('Forfeit – winner has rank 1', !!winner));
  results.push(pass('Forfeit – winner is the remaining player',
    winner?.playerId === hfId, `got=${winner?.playerId} expected=${hfId}`));
  results.push(pass('Forfeit – winner score is a number (not null)',
    typeof winner?.score === 'number', `score=${winner?.score}`));

  // ── Multiple leave/rejoin cycles – no duplicate events ────────────────────
  const hc = await makeClient('H-CYCLE');
  const pc = await makeClient('P-CYCLE');
  send(hc.ws, 'create_room', { displayName: 'CycleHost' });
  await wait(150);
  const cycCode     = last(hc.events, 'room_update')?.data?.code;
  send(pc.ws, 'join_room', { roomCode: cycCode, displayName: 'CyclePlayer' });
  await wait(150);
  // first() — personal join room_update with localPlayerId
  const cycPlayerId = first(pc.events, 'room_update')?.data?.localPlayerId;
  send(hc.ws, 'start_game');
  await wait(200);

  // Cycle 1
  send(pc.ws, 'exit_game_to_home');
  await wait(150);
  const pc2 = await makeClient('P-CYCLE-2');
  send(pc2.ws, 'check_presence', { playerId: cycPlayerId, roomCode: cycCode });
  await wait(200);

  // Cycle 2
  send(pc2.ws, 'exit_game_to_home');
  await wait(150);
  const pc3 = await makeClient('P-CYCLE-3');
  send(pc3.ws, 'check_presence', { playerId: cycPlayerId, roomCode: cycCode });
  await wait(200);

  // After 2 cycles, player should receive exactly 1 personal game_state (the reconnect).
  // (There's also a broadcast game_state, so total may be 2 — filter by localPlayerId.)
  const pc3GameEvents = pc3.events.filter(e => e.event === 'game_state');
  const pc3PersonalGame = pc3GameEvents.filter(e => e.data?.localPlayerId === cycPlayerId);
  results.push(pass('Case 12 – reconnect delivers exactly 1 personal game_state',
    pc3PersonalGame.length === 1, `got ${pc3PersonalGame.length}`));

  const pc3InRoom = last(hc.events, 'room_update')?.data?.players?.find(p => p.id === cycPlayerId);
  results.push(pass('Case 12 – player stays connected after 2 reconnect cycles',
    pc3InRoom?.isConnected === true));

  // ── Summary ────────────────────────────────────────────────────────────────
  const total  = results.length;
  const passed = results.filter(Boolean).length;
  console.log(`\n=== ${passed}/${total} passed ===`);
  if (passed < total) process.exit(1);

  [host, player, reconnClient, permClient, h2, h2Perm, p2, hf, pf, pfPerm,
   hc, pc, pc2, pc3].forEach(c => { try { c.ws.close(); } catch(_) {} });
  process.exit(0);
}

run().catch(e => { console.error(e); process.exit(1); });
