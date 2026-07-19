const WebSocket = require("ws");
function send(ws, event, data) { ws.send(JSON.stringify({ event, data: data || {} })); }
function wait(ms) { return new Promise(r => setTimeout(r, ms)); }
async function run() {
  const p = await new Promise(resolve => {
    const ws = new WebSocket("ws://localhost:3000");
    const events = [];
    ws.on("open", () => resolve({ ws, events }));
    ws.on("message", raw => events.push(JSON.parse(raw.toString())));
  });
  send(p.ws, "join_room", { roomCode: "LQBCRT", displayName: "ScriptPlayer" });
  await wait(500);
  console.log("JOINED");
  // Stay alive for 10 minutes
  await new Promise(r => setTimeout(r, 600000));
  p.ws.close();
}
run().catch(e => { console.error(e); process.exit(1); });
