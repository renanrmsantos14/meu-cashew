// Uso: node shot.mjs <build/web> <saida_dir> <roteiro.json>
// roteiro: [{acao:"goto"|"clicar"|"texto"|"esperar"|"print"|"tecla", alvo, nome, ms, w, h, escuro}]
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire('C:/Users/mendo/AppData/Roaming/npm/node_modules/@playwright/cli/node_modules/x.js');
const { chromium } = require('playwright-core');

const [web, saida, roteiroArq] = process.argv.slice(2);
const roteiro = JSON.parse(fs.readFileSync(roteiroArq, 'utf8'));
fs.mkdirSync(saida, { recursive: true });
const tipos = { '.js': 'text/javascript', '.mjs': 'text/javascript', '.html': 'text/html', '.json': 'application/json', '.wasm': 'application/wasm', '.css': 'text/css', '.png': 'image/png', '.ttf': 'font/ttf', '.otf': 'font/otf', '.svg': 'image/svg+xml' };
const srv = http.createServer((req, res) => {
  let u = decodeURIComponent(req.url.split('?')[0]).replace(/^\/app/, '');
  if (u === '' || u.endsWith('/')) u += 'index.html';
  const f = path.join(web, u);
  if (!fs.existsSync(f)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'content-type': tipos[path.extname(f)] || 'application/octet-stream' });
  fs.createReadStream(f).pipe(res);
}).listen(0);
const porta = srv.address().port;
const exe = 'C:/Users/mendo/AppData/Local/ms-playwright/chromium-1243/chrome-win64/chrome.exe';
const browser = await chromium.launch({ executablePath: fs.existsSync(exe) ? exe : undefined, channel: fs.existsSync(exe) ? undefined : 'chrome', args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
let ctx, page;
async function novo(w = 390, h = 844, escuro = false) {
  if (ctx) await ctx.close();
  ctx = await browser.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: 2, colorScheme: escuro ? 'dark' : 'light' });
  page = await ctx.newPage();
  page.on('pageerror', e => console.log('pageerror', e.message.slice(0, 200)));
}
await novo();
for (const p of roteiro) {
  try {
    if (p.acao === 'contexto') await novo(p.w, p.h, p.escuro);
    if (p.acao === 'goto') { await page.goto(`http://localhost:${porta}/app/${p.alvo || ''}`); await page.waitForTimeout(p.ms || 6000); await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()); await page.waitForTimeout(800); }
    if (p.acao === 'clicar') { await page.getByRole(p.papel || 'button', { name: p.alvo, exact: !!p.exato }).first().click({ timeout: 5000 }); await page.waitForTimeout(p.ms || 1200); }
    if (p.acao === 'clicarTexto') { await page.getByText(p.alvo, { exact: !!p.exato }).first().click({ timeout: 5000 }); await page.waitForTimeout(p.ms || 1200); }
    if (p.acao === 'xy') { await page.mouse.click(p.x, p.y); await page.waitForTimeout(p.ms || 1200); }
    if (p.acao === 'texto') { await page.keyboard.type(p.alvo); await page.waitForTimeout(400); }
    if (p.acao === 'tecla') { await page.keyboard.press(p.alvo); await page.waitForTimeout(p.ms || 800); }
    if (p.acao === 'esperar') await page.waitForTimeout(p.ms);
    if (p.acao === 'print') { await page.screenshot({ path: path.join(saida, p.nome + '.png') }); console.log('print', p.nome); }
    if (p.acao === 'rotulos') { const r = await page.$$eval('flt-semantics [aria-label], flt-semantics[role]', els => els.map(e => (e.getAttribute('role') || '') + ':' + (e.getAttribute('aria-label') || e.textContent || '').trim().slice(0, 40)).filter(x => x.length > 2)); console.log(r.join(' | ').slice(0, 2500)); }
  } catch (e) { console.log('falhou', JSON.stringify(p), e.message.split('\n')[0]); }
}
await browser.close();
srv.close();
