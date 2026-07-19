const { chromium } = require("playwright");
(async () => {
  const ctx = await chromium.launchPersistentContext("C:\\tmp\\playwright-profile3", {
    headless: false,
    executablePath: "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
    args: ["--no-sandbox", "--no-first-run"],
    viewport: { width: 900, height: 900 },
  });
  const page = ctx.pages()[0] || await ctx.newPage();

  await page.goto("http://192.168.6.140:8080", { timeout: 120000, waitUntil: "networkidle" });
  await new Promise(r => setTimeout(r, 4000));

  // Enable Flutter accessibility via JS dispatch
  const a11yEnabled = await page.evaluate(() => {
    function findInShadow(root, sel) {
      const el = root.querySelector(sel);
      if (el) return el;
      for (const child of root.querySelectorAll("*")) {
        if (child.shadowRoot) {
          const found = findInShadow(child.shadowRoot, sel);
          if (found) return found;
        }
      }
      return null;
    }
    const btn = findInShadow(document, "flt-semantics-placeholder");
    if (btn) {
      btn.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
      return true;
    }
    return false;
  });
  console.log("Accessibility enable dispatched:", a11yEnabled);
  await new Promise(r => setTimeout(r, 3000));

  // Now query full semantics tree
  const buttons = await page.evaluate(() => {
    const results = [];
    function walk(root) {
      root.querySelectorAll("[role='button']").forEach(el => {
        results.push({
          tag: el.tagName,
          label: el.getAttribute("aria-label"),
          text: el.textContent?.trim().slice(0, 80),
          rect: el.getBoundingClientRect ? { x: el.getBoundingClientRect().x, y: el.getBoundingClientRect().y } : null
        });
      });
      root.querySelectorAll("*").forEach(el => {
        if (el.shadowRoot) walk(el.shadowRoot);
      });
    }
    walk(document);
    return results.slice(0, 20);
  });
  console.log("Buttons in semantics tree:", JSON.stringify(buttons, null, 2));

  const inputs = await page.evaluate(() => {
    const results = [];
    function walk(root) {
      root.querySelectorAll("input").forEach(el => {
        results.push({ tag: el.tagName, type: el.type, placeholder: el.placeholder });
      });
      root.querySelectorAll("*").forEach(el => {
        if (el.shadowRoot) walk(el.shadowRoot);
      });
    }
    walk(document);
    return results;
  });
  console.log("Inputs:", JSON.stringify(inputs, null, 2));

  await page.screenshot({ path: "C:/tmp/diag5.png" });
  console.log("Screenshot saved");
  await new Promise(r => setTimeout(r, 2000));
  await ctx.close();
})().catch(e => { console.error("FATAL:", e.message); process.exit(1); });
