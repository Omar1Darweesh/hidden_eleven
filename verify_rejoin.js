/**
 * End-to-end rejoin routing verification.
 * Verifies: leave running game → HomeScreen rejoin card → Rejoin → arrives at /game not /lobby.
 *
 * Prerequisites:
 *   - NestJS WS server running on ws://localhost:3000
 *   - Flutter web app served at http://192.168.6.140:8080 (built with SOCKET_URL=ws://localhost:3000)
 *   - Google Chrome installed at default path
 */
const { chromium } = require("playwright");
const WebSocket   = require("ws");

// ── Helpers ───────────────────────────────────────────────────────────────────
function wsClient(label) {
  return new Promise(resolve => {
    const ws = new WebSocket("ws://localhost:3000");
    const ev = [];
    ws.on("open",    ()  => resolve({ ws, ev }));
    ws.on("message", raw => ev.push(JSON.parse(raw.toString())));
    ws.on("error",   e   => console.error(`[${label}] ws error:`, e.message));
  });
}
const send = (ws, event, data) => ws.send(JSON.stringify({ event, data: data || {} }));
const wait = ms => new Promise(r => setTimeout(r, ms));
const last = (ev, n) => [...ev].reverse().find(e => e.event === n);

// Enable Flutter's accessibility semantics tree
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

// Dump all flt-semantics elements for debugging
async function semTexts(page) {
  return page.evaluate(() => {
    const out = [];
    function walk(root) {
      root.querySelectorAll("flt-semantics").forEach(el => {
        const t = el.textContent?.trim();
        const r = el.getBoundingClientRect();
        if (t && r.width > 0) out.push({ role: el.getAttribute("role"), text: t.slice(0,50), x: Math.round(r.x+r.width/2), y: Math.round(r.y+r.height/2) });
      });
      root.querySelectorAll("*").forEach(el => { if (el.shadowRoot) walk(el.shadowRoot); });
    }
    walk(document);
    return out;
  });
}

// Click button by exact text — uses LAST match to avoid header/title elements
async function clickByText(page, text, { first = false } = {}) {
  const elems = await page.evaluate((text) => {
    const out = [];
    function walk(root) {
      root.querySelectorAll("flt-semantics").forEach(el => {
        const t = el.textContent?.trim();
        const r = el.getBoundingClientRect();
        if (t === text && r.width > 0 && r.height > 0)
          out.push({ x: Math.round(r.x + r.width/2), y: Math.round(r.y + r.height/2) });
      });
      root.querySelectorAll("*").forEach(el => { if (el.shadowRoot) walk(el.shadowRoot); });
    }
    walk(document);
    return out;
  }, text);

  const target = first ? elems[0] : elems[elems.length - 1];
  if (!target) { console.log(`  [WARN] No element with text "${text}"`); return false; }
  await page.mouse.click(target.x, target.y);
  return true;
}

// Check if text exists anywhere in Flutter semantics tree
async function hasElem(page, text) {
  return page.evaluate(text => {
    function walk(root) {
      for (const el of root.querySelectorAll("flt-semantics")) {
        if (el.textContent?.trim() === text || el.textContent?.includes(text)) return true;
      }
      for (const el of root.querySelectorAll("*"))
        if (el.shadowRoot && walk(el.shadowRoot)) return true;
      return false;
    }
    return walk(document);
  }, text);
}

// ── Main test ─────────────────────────────────────────────────────────────────
async function run() {
  console.log("=== REJOIN ROUTING VERIFICATION ===\n");

  // ── 1. WS host creates room ───────────────────────────────────────────────
  const hostWs = await wsClient("HOST");
  send(hostWs.ws, "create_room", { displayName: "WSHost" });
  await wait(400);
  const roomCode = last(hostWs.ev, "room_update")?.data?.code;
  if (!roomCode) { console.error("FATAL: no room code"); process.exit(1); }
  console.log("Room created:", roomCode);

  // ── 2. Launch browser ────────────────────────────────────────────────────
  const ctx = await chromium.launchPersistentContext("C:\\tmp\\vr-run5", {
    headless: false,
    executablePath: "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
    args: ["--no-sandbox", "--no-first-run"],
    viewport: { width: 900, height: 900 },
  });
  const page = ctx.pages()[0] || await ctx.newPage();

  console.log("Loading Flutter web app...");
  await page.goto("http://192.168.6.140:8080", { timeout: 120000, waitUntil: "networkidle" });
  await wait(3000);
  await enableA11y(page);
  console.log("App loaded. URL:", page.url());
  await page.screenshot({ path: "C:/tmp/vr0_home.png" });

  // ── 3. Enter name & join room ────────────────────────────────────────────
  console.log("\n[JOIN] Filling display name...");
  // Click the display name field (roughly at y=340, center of viewport) then type
  await page.mouse.click(450, 340);
  await wait(400);
  const nameIn = page.locator("input").first();
  await nameIn.waitFor({ timeout: 10000 }).catch(() => {});
  await nameIn.fill("WebPlayer").catch(async () => {
    // fallback: type directly if fill fails (field may not be a real input until focused)
    await page.keyboard.type("WebPlayer");
  });
  await wait(300);

  // Click "Join Room" on HomeScreen (the button, not the title)
  await clickByText(page, "Join Room", { first: false });
  await wait(1500);

  // Fill room code (now on JoinRoomScreen)
  const codeInput = page.locator("input").first();
  await codeInput.clear();
  await codeInput.fill(roomCode);
  await wait(400);

  // Submit — click the LAST "Join Room" (the submit button, not the title)
  await clickByText(page, "Join Room", { first: false });
  await wait(2500);

  const urlLobby = page.url();
  const playerData = last(hostWs.ev, "room_update")?.data?.players?.find(p => !p.isHost);
  const joinedOK = urlLobby.includes("lobby") && !!playerData;
  console.log(`[JOIN] URL=${urlLobby}  player=${playerData?.displayName}  OK=${joinedOK}`);
  await page.screenshot({ path: "C:/tmp/vr1_lobby.png" });

  if (!joinedOK) {
    const ui = await semTexts(page);
    console.log("UI dump:", JSON.stringify(ui.slice(0,10)));
    console.error("BLOCKED: player did not join room — cannot continue");
    await ctx.close(); process.exit(1);
  }

  // ── 4. Host starts game ──────────────────────────────────────────────────
  console.log("\n[START GAME] Host sending start_game...");
  send(hostWs.ws, "start_game");
  await wait(2500);

  const urlGame = page.url();
  const inGameByUrl = urlGame.includes("game");
  console.log(`[START GAME] URL=${urlGame}  inGame=${inGameByUrl}`);
  await page.screenshot({ path: "C:/tmp/vr2_game.png" });

  // ── 5. Player leaves game → HomeScreen ──────────────────────────────────
  console.log("\n[LEAVE] Clicking Leave...");
  await clickByText(page, "Leave");
  await wait(2000);

  const urlAfterLeave = page.url();
  console.log(`[LEAVE] URL=${urlAfterLeave}`);
  await page.screenshot({ path: "C:/tmp/vr3_after_leave.png" });

  const ui = await semTexts(page);
  const hasRejoinCard = ui.some(e => e.text.includes("Rejoin") || e.text.includes("ACTIVE") || e.text.includes("Active Game"));
  const hasHostBtn    = ui.some(e => e.text === "Host Room");
  console.log(`[LEAVE] rejoinCard=${hasRejoinCard}  hostBtnVisible=${hasHostBtn}`);
  if (!hasRejoinCard) console.log("  UI:", JSON.stringify(ui.map(e=>e.text).slice(0,15)));

  // ── 6. Tap Rejoin Game ───────────────────────────────────────────────────
  console.log("\n[REJOIN] Tapping Rejoin...");
  let rejoinClicked = await clickByText(page, "Rejoin Game");
  if (!rejoinClicked) rejoinClicked = await clickByText(page, "Rejoin");
  if (!rejoinClicked) {
    const allTexts = ui.map(e => e.text);
    console.log("  All UI texts:", allTexts);
  }
  await wait(3500);

  const urlAfterRejoin = page.url();
  const backInGame  = urlAfterRejoin.includes("game");
  const stuckLobby  = urlAfterRejoin.includes("lobby");
  console.log(`[REJOIN] URL=${urlAfterRejoin}  backInGame=${backInGame}  stuckLobby=${stuckLobby}`);
  await page.screenshot({ path: "C:/tmp/vr4_after_rejoin.png" });

  // ── 7. Confirm no duplicate navigation (stays in game) ──────────────────
  await wait(2000);
  const urlFinal = page.url();
  const staysInGame = urlFinal.includes("game");
  console.log(`[STABLE] URL=${urlFinal}  staysInGame=${staysInGame}`);

  // ── 8. Leave permanently ─────────────────────────────────────────────────
  if (backInGame) {
    console.log("\n[PERM LEAVE] Clicking Leave → Leave Permanently...");
    await clickByText(page, "Leave");
    await wait(1000);
    await clickByText(page, "Leave Permanently");
    await wait(2000);
    const urlPerm = page.url();
    const cardGone = !(await hasElem(page, "Rejoin Game"));
    const hostBack  = await hasElem(page, "Host Room");
    console.log(`[PERM LEAVE] URL=${urlPerm}  cardGone=${cardGone}  hostBtnBack=${hostBack}`);
    await page.screenshot({ path: "C:/tmp/vr5_perm_leave.png" });
  }

  // ── RESULTS ──────────────────────────────────────────────────────────────
  console.log("\n=== RESULTS ===");
  const r1 = joinedOK;
  const r2 = inGameByUrl;
  const r3 = hasRejoinCard;
  const r4 = !hasHostBtn;
  const r5 = backInGame && !stuckLobby;
  const r6 = staysInGame;

  console.log("1. Player joined & lobby URL (#/lobby)  :", r1 ? "PASS" : "FAIL");
  console.log("2. Game started & game URL (#/game)     :", r2 ? "PASS" : "FAIL");
  console.log("3. Rejoin card appeared after leave      :", r3 ? "PASS" : "FAIL/UNKNOWN");
  console.log("4. Host/Join hidden while card shows     :", r4 ? "PASS" : "FAIL/UNKNOWN");
  console.log("5. Rejoin routes to /game (not /lobby)  :", r5 ? "PASS" : "FAIL  ← THE BUG");
  console.log("6. Stays in /game (no duplicate nav)    :", r6 ? "PASS" : "FAIL");

  const PASS = r1 && r2 && r5 && r6;
  console.log("\nOVERALL:", PASS ? "✓ PASS — safe to move to Phase 5" : "✗ FAIL");

  await wait(3000);
  hostWs.ws.close();
  await ctx.close();
  process.exit(PASS ? 0 : 1);
}

run().catch(e => { console.error("FATAL:", e.message); process.exit(1); });
