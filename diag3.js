const { chromium } = require("playwright");
(async () => {
  console.log("Launching Chrome (headless:false)...");
  const ctx = await chromium.launchPersistentContext("C:\\tmp\\playwright-profile", {
    headless: false,
    executablePath: "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
    args: ["--no-sandbox", "--disable-setuid-sandbox", "--no-first-run", "--no-default-browser-check"],
    viewport: { width: 900, height: 900 },
  });
  const browser = null; // using persistent context directly
  const page = ctx.pages()[0] || await ctx.newPage();
  console.log("Navigating to http://192.168.6.140:8080 (built app, networkidle)...");
  try {
    await page.goto("http://192.168.6.140:8080", { timeout: 120000, waitUntil: "networkidle" });
    console.log("networkidle reached. URL:", page.url());
  } catch(e) {
    console.log("goto error:", e.message, "- continuing anyway");
  }
  console.log("Waiting 5s more for Flutter...");
  await new Promise(r => setTimeout(r, 5000));
  const fltGlass = await page.evaluate(() => !!document.querySelector("flt-glass-pane"));
  const allCustomEls = await page.evaluate(() => {
    const els = document.querySelectorAll("*");
    const custom = new Set();
    for (const el of els) { if (el.tagName.includes("-")) custom.add(el.tagName.toLowerCase()); }
    return [...custom].slice(0, 20);
  });
  console.log("flt-glass-pane:", fltGlass);
  console.log("Custom elements:", allCustomEls);
  const url = page.url();
  console.log("Final URL:", url);
  await page.screenshot({ path: "C:/tmp/diag3.png" });
  console.log("Screenshot saved");
  await new Promise(r => setTimeout(r, 3000));
  await ctx.close();
})().catch(e => { console.error("FATAL:", e.message); process.exit(1); });
