import { readFileSync, writeFileSync, mkdirSync } from 'fs';
import { pipeline } from 'stream/promises';
import { Readable } from 'stream';
import { createWriteStream } from 'fs';
import path from 'path';

const UA = 'HiddenEleven-PlayerPhotoResearch/1.0 (contact: omaryy0903@gmail.com)';
const OUT_DIR = './assets/players/photos/wikimedia';
mkdirSync(OUT_DIR, { recursive: true });

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }
function extFromUrl(url) {
  const m = url.match(/\.(jpg|jpeg|png|webp)(?:\?|$)/i);
  return m ? m[1].toLowerCase().replace('jpeg', 'jpg') : 'jpg';
}

const attributions = JSON.parse(readFileSync('../scripts/player-photos/attributions.json', 'utf8'));
const failed = JSON.parse(readFileSync('../scripts/player-photos/download-failed.json', 'utf8'));
const downloaded = JSON.parse(readFileSync('../scripts/player-photos/downloaded.json', 'utf8'));

const stillFailed = [];
let i = 0;
for (const f of failed) {
  i++;
  if (i % 25 === 0) console.error(`... ${i}/${failed.length}`);
  const entry = attributions[f.id];
  const ext = extFromUrl(entry.attribution.directUrl);
  const filename = `${entry.id}.${ext}`;
  const outPath = path.join(OUT_DIR, filename);
  let ok = false;
  for (let attempt = 0; attempt < 5 && !ok; attempt++) {
    try {
      const res = await fetch(entry.attribution.directUrl, { headers: { 'User-Agent': UA } });
      if (res.status === 429) { await sleep(2000 * (attempt + 1)); continue; }
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      await pipeline(Readable.fromWeb(res.body), createWriteStream(outPath));
      downloaded.push({ id: entry.id, name: entry.name, localPath: `/assets/players/photos/wikimedia/${filename}`, attribution: entry.attribution });
      ok = true;
    } catch (e) {
      if (attempt === 4) stillFailed.push({ id: f.id, name: f.name, error: String(e) });
      await sleep(1000);
    }
  }
  await sleep(400); // slower pace this time to respect rate limits
}

writeFileSync('../scripts/player-photos/downloaded.json', JSON.stringify(downloaded, null, 2));
writeFileSync('../scripts/player-photos/download-failed.json', JSON.stringify(stillFailed, null, 2));
console.error(`\nDone. Total downloaded now: ${downloaded.length}, Still failed: ${stillFailed.length}`);
