// Opens every exported product in real browser engines and checks that it works:
// no uncaught errors, the built-in selfTest passes, games animate, apps respond to clicks.
// Usage: node tools/verify-templates.mjs <export-folder> [chromium,webkit] [screenshots-folder]
import { createRequire } from 'module';
import fs from 'fs';
import path from 'path';
const require = createRequire(import.meta.url);
const { chromium, webkit } = require('playwright');

const root = process.argv[2];
const engines = (process.argv[3] || 'chromium').split(',');
const shots = process.argv[4];
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json'), 'utf8'));
let failures = 0;
let checked = 0;

for (const engineName of engines) {
  const engine = { chromium, webkit }[engineName];
  let browser;
  try { browser = await engine.launch(); } catch (e) { console.log(`SKIP ${engineName}: ${e.message.split('\n')[0]}`); continue; }
  for (const item of manifest) {
    const page = await browser.newPage({ viewport: { width: 900, height: 900 } });
    const errors = [];
    page.on('pageerror', e => errors.push('pageerror: ' + e.message));
    page.on('console', m => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
    const url = 'file://' + path.resolve(root, item.folder, 'index.html');
    let result = { ok: false, details: ['not run'] };
    let animated = null;
    try {
      await page.goto(url);
      await page.waitForTimeout(400);
      const api = await page.evaluate(() => window.__game ? 'game' : (window.__app ? 'app' : 'none'));
      if (api === 'game') {
        result = await page.evaluate(() => window.__game.selfTest());
        // Liveness: start a fresh game and see the picture change over time.
        await page.evaluate(() => { window.__game.begin(); });
        const a = await page.evaluate(() => document.getElementById('game').toDataURL());
        await page.waitForTimeout(700);
        await page.evaluate(() => { window.__game.tap('action'); window.__game.tap('right'); });
        await page.waitForTimeout(500);
        const b = await page.evaluate(() => document.getElementById('game').toDataURL());
        animated = a !== b;
      } else if (api === 'app') {
        result = await page.evaluate(() => window.__app.selfTest());
      } else {
        result = { ok: false, details: ['no window.__game / window.__app test hook'] };
      }
      // Click every visible button once (monkey test) and watch for errors.
      const buttons = await page.$$('button:visible');
      for (const btn of buttons.slice(0, 25)) { try { await btn.click({ timeout: 500 }); } catch (e) {} }
      await page.waitForTimeout(300);
      if (shots) {
        fs.mkdirSync(shots, { recursive: true });
        await page.screenshot({ path: path.join(shots, `${engineName}-${item.folder}.png`) });
      }
    } catch (e) {
      errors.push('harness: ' + e.message);
    }
    const ok = result && result.ok && errors.length === 0 && animated !== false;
    checked++;
    if (!ok) failures++;
    console.log(`${ok ? 'PASS' : 'FAIL'} ${engineName} ${item.folder} — ${item.request}`);
    for (const d of (result && result.details) || []) console.log('     ' + d);
    if (animated !== null) console.log(`     ${animated ? '✓' : '✗'} the picture changes while playing`);
    for (const e of errors) console.log('     ✗ ' + e);
    await page.close();
  }
  await browser.close();
}
if (checked === 0) { console.log('NO BROWSER ENGINE AVAILABLE ❌'); process.exit(1); }
console.log(failures === 0 ? `ALL ${checked} PRODUCT CHECKS PASSED ✅` : `${failures} OF ${checked} PRODUCT CHECK(S) FAILED ❌`);
process.exit(failures === 0 ? 0 : 1);
