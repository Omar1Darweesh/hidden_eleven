const { chromium } = require("playwright");
async function run() {
  const browser = await chromium.launch({
    headless: true,
    executablePath: "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
    args: ["--no-sandbox", "--disable-setuid-sandbox", "--enable-unsafe-webgpu"],
  });
  const page = await browser.newPage();
  page.on("console", m => console.log("[browser]", m.text()));
  page.on("pageerror", e => console.log("[pageerror]", e.message));
  await page.goto("http://localhost:8083");
  await page.waitForTimeout(8000);
  const title = await page.title();
  const body = await page.evaluate(() => document.body?.innerHTML?.slice(0,300));
  const url = page.url();
  console.log("url:", url);
  console.log("title:", title);
  console.log("body:", body);
  await page.screenshot({ path: "C:\\Temp\\diag.png" });
  console.log("screenshot saved");
  await browser.close();
}
run().catch(e => console.error(e.message));
