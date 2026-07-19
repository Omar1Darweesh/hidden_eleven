const { chromium } = require("playwright");
(async () => {
  const browser = await chromium.launch({
    headless: true,
    executablePath: "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
    args: ["--no-sandbox"],
  });
  const page = await browser.newPage();
  console.log("Navigating (networkidle wait)...");
  try {
    await page.goto("http://localhost:8083", { timeout: 180000, waitUntil: "networkidle" });
    console.log("Network idle. URL:", page.url());
    const flutterEl = await page.evaluate(() => !!document.querySelector("flt-glass-pane"));
    console.log("flt-glass-pane exists:", flutterEl);
    const innerText = await page.evaluate(() => document.body ? document.body.innerText.slice(0, 200) : "");
    console.log("innerText:", innerText);
    await page.screenshot({ path: "C:/tmp/diag3.png" });
    console.log("Screenshot saved");
  } catch(e) {
    console.error("Error:", e.message);
    await page.screenshot({ path: "C:/tmp/diag3_err.png" }).catch(() => {});
    const flutterEl = await page.evaluate(() => !!document.querySelector("flt-glass-pane")).catch(() => false);
    console.log("flt-glass-pane on error:", flutterEl);
  }
  await browser.close();
})();
