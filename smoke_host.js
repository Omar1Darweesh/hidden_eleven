const WebSocket = require("ws");
function send(ws, event, data) { ws.send(JSON.stringify({ event, data: data || {} })); }
function wait(ms) { return new Promise(r => setTimeout(r, ms)); }
function last(ev, n) { return [...ev].reverse().find(e => e.event === n); }

async function run() {
  const host = await new Promise(resolve => {
    const ws = new WebSocket("ws://localhost:3000");
    const events = [];
    ws.on("open", () => resolve({ ws, events }));
    ws.on("message", raw => events.push(JSON.parse(raw.toString())));
  });

  send(host.ws, "create_room", { displayName: "ScriptHost" });
  await wait(300);
  const roomCode = last(host.events, "room_update")?.data?.code;
  const hostId = last(host.events, "room_update")?.data?.localPlayerId;
  console.log("ROOM_CODE=" + roomCode);
  console.log("HOST_ID=" + hostId);

  // Wait for player to join (poll for 30s)
  let joined = false;
  for (let i = 0; i < 60; i++) {
    await wait(500);
    const room = last(host.events, "room_update")?.data;
    if (room && room.players && room.players.length >= 2) { joined = true; break; }
  }
  if (!joined) { console.log("TIMEOUT: player never joined"); process.exit(1); }
  console.log("PLAYER_JOINED");

  // Start game
  send(host.ws, "start_game");
  await wait(300);
  const gameEvt = last(host.events, "game_state");
  console.log("GAME_STARTED=" + !!gameEvt);

  // Now wait and watch for player disconnect (exit_game_to_home)
  let disconnected = false;
  for (let i = 0; i < 60; i++) {
    await wait(500);
    const roomEvt = last(host.events, "room_update");
    if (roomEvt?.data?.players?.some(p => p.isConnected === false && !p.isHost)) {
      disconnected = true; break;
    }
  }
  console.log("PLAYER_DISCONNECTED=" + disconnected);

  // Wait for reconnect
  let reconnected = false;
  for (let i = 0; i < 60; i++) {
    await wait(500);
    const roomEvt = last(host.events, "room_update");
    if (roomEvt?.data?.players?.every(p => p.isConnected === true)) {
      reconnected = true; break;
    }
  }
  console.log("PLAYER_RECONNECTED=" + reconnected);

  // Wait for permanent leave
  let removed = false;
  for (let i = 0; i < 60; i++) {
    await wait(500);
    const roomEvt = last(host.events, "room_update");
    if (roomEvt?.data?.players?.length === 1) { removed = true; break; }
  }
  console.log("PLAYER_REMOVED=" + removed);
  host.ws.close();
  process.exit(0);
}
run().catch(e => { console.error(e); process.exit(1); });
