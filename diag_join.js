/**
 * Debug the join room flow step by step.
 */
const { chromium } = require("playwright");
const WebSocket = require("ws");

function wsClient() {
  return new Promise(resolve => {
    const ws = new WebSocket("ws://localhost:3000");
    const events = [];
    ws.on("open", () => resolve({ ws, events }));
    ws.on("message", raw => events.push(JSON.parse(raw.toString())));
    ws.on("error", e => console.error("ws error:", e.message));
  });
}
function wsSend(ws, event, data) { ws.send(JSON.stringify({ event, data: data || {} })); }
function wait(ms) { return new Promise(r => setTimeout(r, ms)); }
function last(evs, n) { return [...evs].reverse().find(e => e.event === n); }

async function enableA11y(page) {
  await page.evaluate(() => {
    function find(root, sel) {
      const el = root.querySelector(sel);
      if (el) return el;
      for (const c of root.querySelectorAll("*")) {
        if (c.shadowRoot) { const f = find(c.shadowRoot, sel); if (f) return f; }
      }
    }
    const btn = find(document, "flt-semantics-placeholder");
    if (btn) btn.dispatchEvent(new MouseEvent("click", { bubbles: true }));
  });
  await wait(2000);
}

async function dumpUI(page, label) {
  const texts = await page.evaluate(() => {
    const out = [];
    function walk(root) {
      root.querySelectorAll("flt-semantics").forEach(el => {
        const role = el.getAttribute("role");
        const t = el.textContent?.trim();
        const rect = el.getBoundingClientRect();
        if (t) out.push({ role, text: t.slice(0, 60), x: Math.round(rect.x), y: Math.round(rect.y), w: Math.round(rect.width), h: Math.round(rect.height) });
      });
      root.querySelectorAll("*").forEach(el => { if (el.shadowRoot) walk(el.shadowRoot); });
    }
    walk(document);
    return out;
  });
  console.log(`\n--- UI @ ${label} (URL: ${page.url()}) ---`);
  texts.forEach(t => console.log(` [${t.role||'?'}] "${t.text}" at (${t.x},${t.y})`));

  const inputs = await page.evaluate(() => {
    const out = [];
    function walk(root) {
      root.querySelectorAll("input").forEach(el => {
        out.push({ type: el.type, value: el.value, placeholder: el.placeholder });
      });
      root.querySelectorAll("*").forEach(el => { if (el.shadowRoot) walk(el.shadowRoot); });
    }
    walk(document);
    return out;
  });
  console.log(" Inputs:", JSON.stringify(inputs));
}

async function run() {
  const host = await wsClient();
  wsSend(host.ws, "create_room", { displayName: "WSHost" });
  await wait(400);
  const roomCode = last(host.events, "room_update")?.data?.code;
  console.log("Room:", roomCode);

  const ctx = await chromium.launchPersistentContext("C:\\tmp\\diag-join-profile2", {
    headless: false,
    executablePath: "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
    args: ["--no-sandbox", "--no-first-run"],
    viewport: { width: 900, height: 900 },
  });
  const page = ctx.pages()[0] || await ctx.newPage();
  await page.goto("http://192.168.6.140:8080", { timeout: 120000, waitUntil: "networkidle" });
  await wait(3000);
  await enableA11y(page);

  await dumpUI(page, "HomeScreen");
  await page.screenshot({ path: "C:/tmp/dj00.png" });

  // Fill name input
  const nameIn = page.locator("input").first();
  await nameIn.fill("WebPlayer");
  await wait(300);
  await dumpUI(page, "After name fill");

  // Click Join Room
  const joinBtns = await page.evaluate(() => {
    const out = [];
    function walk(root) {
      root.querySelectorAll("flt-semantics[role='button'], flt-semantics").forEach(el => {
        const t = el.textContent?.trim();
        if (t === "Join Room") {
          const rect = el.getBoundingClientRect();
          out.push({ x: rect.x + rect.width/2, y: rect.y + rect.height/2 });
        }
      });
      root.querySelectorAll("*").forEach(el => { if (el.shadowRoot) walk(el.shadowRoot); });
    }
    walk(document);
    return out;
  });
  console.log("\nJoin Room buttons found:", joinBtns);

  if (joinBtns[0]) {
    await page.mouse.click(joinBtns[0].x, joinBtns[0].y);
    console.log("Clicked Join Room at", joinBtns[0]);
  }
  await wait(1500);

  await dumpUI(page, "After Join Room click");
  await page.screenshot({ path: "C:/tmp/dj01.png" });

  // Now fill room code
  const allInputs = await page.evaluate(() => {
    const out = [];
    function walk(root) {
      root.querySelectorAll("input").forEach(el => {
        const rect = el.getBoundingClientRect();
        out.push({ value: el.value, placeholder: el.placeholder, x: rect.x, y: rect.y });
      });
      root.querySelectorAll("*").forEach(el => { if (el.shadowRoot) walk(el.shadowRoot); });
    }
    walk(document);
    return out;
  });
  console.log("\nAll inputs:", JSON.stringify(allInputs));

  // Fill room code into the visible input
  const codeInput = page.locator("input").first();
  await codeInput.clear();
  await codeInput.fill(roomCode);
  await wait(500);
  await dumpUI(page, "After code fill");

  // Click Join Room again (submit)
  const joinBtns2 = await page.evaluate(() => {
    const out = [];
    function walk(root) {
      root.querySelectorAll("flt-semantics[role='button'], flt-semantics").forEach(el => {
        const t = el.textContent?.trim();
        const rect = el.getBoundingClientRect();
        if (rect.width > 0 && rect.height > 0) {
          out.push({ text: t?.slice(0,30), x: Math.round(rect.x + rect.width/2), y: Math.round(rect.y + rect.height/2) });
        }
      });
      root.querySelectorAll("*").forEach(el => { if (el.shadowRoot) walk(el.shadowRoot); });
    }
    walk(document);
    return out.filter(b => b.text);
  });
  console.log("\nAll buttons with coords:", JSON.stringify(joinBtns2));

  // Find the LAST "Join Room" button (the submit button, not the back/title)
  const submitBtn = [...joinBtns2].reverse().find(b => b.text === "Join Room");
  if (submitBtn) {
    console.log("Clicking submit Join Room at", submitBtn);
    await page.mouse.click(submitBtn.x, submitBtn.y);
  }
  await wait(3000);

  await dumpUI(page, "After submit");
  await page.screenshot({ path: "C:/tmp/dj02.png" });
  const urlFinal = page.url();
  console.log("\nFinal URL:", urlFinal);
  const joined = last(host.events, "room_update")?.data?.players?.find(p => !p.isHost);
  console.log("Player joined:", joined ? `YES (${joined.displayName})` : "NO");

  host.ws.close();
  await wait(2000);
  await ctx.close();
}

run().catch(e => { console.error("FATAL:", e.message); process.exit(1); });
