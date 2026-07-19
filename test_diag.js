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
    ws.on('error', (e) => console.error('[' + label + '] error', e.message));
    ws.on('close', () => console.log('[' + label + '] socket closed'));
  });
}
function send(ws, event, data) { ws.send(JSON.stringify({ event, data: data || {} })); }
function wait(ms) { return new Promise(r => setTimeout(r, ms)); }
function last(events, eventName) { return [...events].reverse().find(e => e.event === eventName); }

async function run() {
  const host   = await makeClient('HOST');
  const player = await makeClient('PLAYER');

  send(host.ws, 'create_room', { displayName: 'HostUser' });
  await wait(200);
  const hostRoom1 = last(host.events, 'room_update');
  const roomCode  = hostRoom1?.data?.code;
  const hostId    = hostRoom1?.data?.localPlayerId;
  console.log('Room:', roomCode, 'hostId:', hostId);

  send(player.ws, 'join_room', { roomCode, displayName: 'PlayerUser' });
  await wait(200);
  const playerRoom1 = last(player.events, 'room_update');
  const playerId    = playerRoom1?.data?.localPlayerId;
  console.log('Player joined, playerId:', playerId);

  send(host.ws, 'start_game');
  await wait(300);
  console.log('Game started');
  console.log('  host game_state localPlayerId:', last(host.events, 'game_state')?.data?.localPlayerId);
  console.log('  player game_state localPlayerId:', last(player.events, 'game_state')?.data?.localPlayerId);

  console.log('\n--- exit_game_to_home ---');
  send(player.ws, 'exit_game_to_home');
  await wait(400);

  const hostRoomAfter = last(host.events, 'room_update');
  const hostGameAfter = last(host.events, 'game_state');
  console.log('host room_update received:', !!hostRoomAfter);
  console.log('host game_state received:', !!hostGameAfter);
  console.log('host room players:', JSON.stringify(hostRoomAfter?.data?.players));
  console.log('host game players:', JSON.stringify(hostGameAfter?.data?.players));

  console.log('\n--- check_presence ---');
  const p2 = await makeClient('PLAYER2');
  send(p2.ws, 'check_presence', { playerId, roomCode });
  await wait(400);
  console.log('p2 room_update:', !!last(p2.events, 'room_update'));
  console.log('p2 game_state:', !!last(p2.events, 'game_state'));
  console.log('p2 error:', last(p2.events, 'error'));
  console.log('p2 all events:', p2.events.map(e => e.event));

  [host, player, p2].forEach(c => { try { c.ws.close(); } catch(_) {} });
  process.exit(0);
}
run().catch(e => { console.error(e); process.exit(1); });
