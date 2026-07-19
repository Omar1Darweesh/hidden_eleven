const { chromium } = require("playwright");
(async () => {
  const ctx = await chromium.launchPersistentContext("C:\\tmp\\playwright-profile2", {
    headless: false,
    executablePath: "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
    args: ["--no-sandbox", "--no-first-run"],
    viewport: { width: 900, height: 900 },
  });
  const page = ctx.pages()[0] || await ctx.newPage();

  await page.goto("http://192.168.6.140:8080", { timeout: 120000, waitUntil: "networkidle" });
  await new Promise(r => setTimeout(r, 5000));

  // Query shadow DOM for semantics elements with button text
  const semInfo = await page.evaluate(() => {
    function queryAllShadow(root, sel) {
      const results = [];
      function walk(node) {
        node.querySelectorAll(sel).forEach(el => results.push({
          tag: el.tagName,
          role: el.getAttribute("role"),
          label: el.getAttribute("aria-label"),
          text: el.textContent?.slice(0, 80)
        }));
        node.querySelectorAll("*").forEach(el => {
          if (el.shadowRoot) walk(el.shadowRoot);
        });
      }
      walk(root);
      return results;
    }
    return queryAllShadow(document, "[role='button'], button, flt-semantics");
  });
  console.log("Semantic elements found:", JSON.stringify(semInfo.slice(0, 20), null, 2));

  // Try Playwright's built-in locator
  const hostBtn = page.getByRole("button", { name: /host room/i });
  const visible = await hostBtn.isVisible().catch(() => false);
  console.log("getByRole('button', 'Host Room') visible:", visible);

  const txtLoc = page.locator("text=Host Room");
  const txtVisible = await txtLoc.first().isVisible({ timeout: 5000 }).catch(() => false);
  console.log("locator('text=Host Room') visible:", txtVisible);

  await page.screenshot({ path: "C:/tmp/diag4.png" });
  await ctx.close();
})().catch(e => { console.error("FATAL:", e.message); process.exit(1); });
