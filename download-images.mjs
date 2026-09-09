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
const entries = Object.values(attributions).filter(a => a.attribution?.directUrl);

const downloaded = [];
const failed = [];
let i = 0;

for (const entry of entries) {
  i++;
  if (i % 25 === 0) console.error(`... ${i}/${entries.length}`);
  const ext = extFromUrl(entry.attribution.directUrl);
  const filename = `${entry.id}.${ext}`;
  const outPath = path.join(OUT_DIR, filename);
  try {
    const res = await fetch(entry.attribution.directUrl, { headers: { 'User-Agent': UA } });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    await pipeline(Readable.fromWeb(res.body), createWriteStream(outPath));
    downloaded.push({ id: entry.id, name: entry.name, localPath: `/assets/players/photos/wikimedia/${filename}`, attribution: entry.attribution });
  } catch (e) {
    failed.push({ id: entry.id, name: entry.name, error: String(e) });
  }
  await sleep(100);
}

writeFileSync('../scripts/player-photos/downloaded.json', JSON.stringify(downloaded, null, 2));
writeFileSync('../scripts/player-photos/download-failed.json', JSON.stringify(failed, null, 2));
console.error(`\nDone. Downloaded: ${downloaded.length}, Failed: ${failed.length}`);
