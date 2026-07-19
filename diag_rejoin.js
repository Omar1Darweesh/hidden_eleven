/**
 * Isolates and debugs the rejoin card state.
 */
const { chromium } = require("playwright");
const WebSocket   = require("ws");

function wsClient(label) {
  return new Promise(resolve => {
    const ws = new WebSocket("ws://localhost:3000");
    const ev = [];
    ws.on("open", () => resolve({ ws, ev }));
    ws.on("message", raw => ev.push(JSON.parse(raw.toString())));
    ws.on("error", e => console.error(`[${label}]`, e.message));
  });
}
const send = (ws, event, data) => ws.send(JSON.stringify({ event, data: data || {} }));
const wait = ms => new Promise(r => setTimeout(r, ms));
const last = (ev, n) => [...ev].reverse().find(e => e.event === n);

async function enableA11y(page) {
  await page.evaluate(() => {
    function find(root, sel) {
      const el = root.querySelector(sel);
      if (el) return el;
      for (const c of root.querySelectorAll("*"))
        if (c.shadowRoot) { const f = find(c.shadowRoot, sel); if (f) return f; }
    }
    const btn = find(document, "flt-semantics-placeholder");
    if (btn) btn.dispatchEvent(new MouseEvent("click", { bubbles: true }));
  });
  await wait(2000);
}

async function dumpAll(page) {
  return page.evaluate(() => {
    const out = [];
    function walk(root) {
      root.querySelectorAll("flt-semantics").forEach(el => {
        const t = el.textContent?.trim();
        const r = el.getBoundingClientRect();
        out.push({
          role: el.getAttribute("role"),
          label: el.getAttribute("aria-label"),
          text: t?.slice(0, 80),
          x: Math.round(r.x + r.width/2),
          y: Math.round(r.y + r.height/2),
          w: Math.round(r.width), h: Math.round(r.height)
        });
      });
      root.querySelectorAll("*").forEach(el => { if (el.shadowRoot) walk(el.shadowRoot); });
    }
    walk(document);
    return out;
  });
}

async function clickBtn(page, text) {
  const elems = await page.evaluate((text) => {
    const out = [];
    function walk(root) {
      root.querySelectorAll("flt-semantics").forEach(el => {
        const t = el.textContent?.trim();
        const r = el.getBoundingClientRect();
        if (r.width > 0 && r.height > 0)
          out.push({ text: t?.slice(0,80), x: Math.round(r.x+r.width/2), y: Math.round(r.y+r.height/2) });
      });
      root.querySelectorAll("*").forEach(el => { if (el.shadowRoot) walk(el.shadowRoot); });
    }
    walk(document);
    return out;
  }, text);
  // Find last exact match
  const match = [...elems].reverse().find(e => e.text === text);
  if (match) { await page.mouse.click(match.x, match.y); return match; }
  // Try startsWith
  const partial = [...elems].reverse().find(e => e.text?.startsWith(text));
  if (partial) { await page.mouse.click(partial.x, partial.y); console.log("  (partial match:", partial.text, ")"); return partial; }
  console.log(`  [WARN] No element with text "${text}"`);
  return null;
}

async function run() {
  const host = await wsClient("HOST");
  send(host.ws, "create_room", { displayName: "WSHost" });
  await wait(400);
  const roomCode = last(host.ev, "room_update")?.data?.code;
  console.log("Room:", roomCode);

  const ctx = await chromium.launchPersistentContext("C:\\tmp\\dr-profile", {
    headless: false,
    executablePath: "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
    args: ["--no-sandbox", "--no-first-run"],
    viewport: { width: 900, height: 900 },
  });
  const page = ctx.pages()[0] || await ctx.newPage();
  await page.goto("http://192.168.6.140:8080", { timeout: 120000, waitUntil: "networkidle" });
  await wait(3000);
  await enableA11y(page);

  // Fill name and join
  await page.locator("input").first().fill("WebPlayer");
  await wait(300);
  await clickBtn(page, "Join Room"); // HomeScreen button
  await wait(1500);
  const codeIn = page.locator("input").first();
  await codeIn.clear(); await codeIn.fill(roomCode);
  await wait(400);
  await clickBtn(page, "Join Room"); // submit (last match)
  await wait(2500);
  console.log("\nLobby URL:", page.url());

  // Start game
  send(host.ws, "start_game");
  await wait(2500);
  console.log("Game URL:", page.url());
  await page.screenshot({ path: "C:/tmp/dr_game.png" });

  // Leave
  await clickBtn(page, "Leave");
  await wait(2500);
  console.log("After leave URL:", page.url());
  await page.screenshot({ path: "C:/tmp/dr_after_leave.png" });

  // DUMP ALL ELEMENTS
  const ui = await dumpAll(page);
  console.log("\n=== UI AFTER LEAVE ===");
  ui.forEach(e => {
    if (e.w > 0) console.log(`  [${e.role||e.label||'?'}] "${e.text}" at (${e.x},${e.y}) ${e.w}x${e.h}`);
  });

  // Click rejoin
  console.log("\nClicking Rejoin...");
  const clicked = await clickBtn(page, "Rejoin Game");
  console.log("Clicked:", JSON.stringify(clicked));
  await wait(4000);
  console.log("URL after rejoin:", page.url());
  await page.screenshot({ path: "C:/tmp/dr_after_rejoin.png" });

  // Check WS events received after rejoin
  const eventsAfterRejoin = host.ev.filter(e => ["room_update","game_state","check_presence"].includes(e.event));
  console.log("\nWS events (host side):", JSON.stringify(eventsAfterRejoin.map(e=>({event:e.event, players:e.data?.players?.length})), null, 2));

  host.ws.close();
  await wait(2000);
  await ctx.close();
}

run().catch(e => { console.error("FATAL:", e.message); process.exit(1); });
