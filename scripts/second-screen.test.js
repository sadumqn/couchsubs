// SPDX-License-Identifier: AGPL-3.0-only
// İkinci ekran sayfasının (core/Sources/CouchSubsCore/Resources/second-screen.html) uçtan uca denemesi: gerçek
// Chromium, sayfayı yerel bir HTTP sunucusundan anahtarlı adresle açar, /events akışından (SSE) gelen altyazıyı çizer.
// node --test scripts/second-screen.test.js — tarayıcı yolu: COUCHSUBS_TEST_BROWSER; yalnız 127.0.0.1, internet yok.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const page = path.join(__dirname, '..', 'core', 'Sources', 'CouchSubsCore', 'Resources', 'second-screen.html');
const browser = [process.env.COUCHSUBS_TEST_BROWSER, process.env.CHROME_BIN,
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  '/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'].find(p => p && fs.existsSync(p));

const KEY = 'dogru-anahtar';

// Uygulamadaki sunucunun bu sayfa için yaptığı: anahtarsız sayfa ve akış 401; akış önce stili, sonra altyazıyı verir.
function serve(events) {
  const seen = { streams: 0, streamKey: null };
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://127.0.0.1');
    if (url.searchParams.get('k') !== KEY) { res.writeHead(401); res.end(); return; }
    if (url.pathname === '/view') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(fs.readFileSync(page));
    } else if (url.pathname === '/events' && url.searchParams.get('viewer') === 'second') {
      seen.streams++;
      seen.streamKey = url.searchParams.get('k');
      res.writeHead(200, { 'Content-Type': 'text/event-stream; charset=utf-8', 'Cache-Control': 'no-cache' });
      res.write('retry: 60000\n\n');
      for (const [name, data] of events) res.write(`event: ${name}\ndata: ${JSON.stringify(data)}\n\n`);
      // Akış kapanır: tarayıcının "sayfa yüklendi" saymasını bekleten açık bağlantı kalmasın (yeniden bağlanma 60 sn sonra).
      setTimeout(() => res.end(), 300);
    } else { res.writeHead(404); res.end(); }
  });
  return new Promise(resolve => server.listen(0, '127.0.0.1', () => resolve({ server, seen, port: server.address().port })));
}

function dump(url, { width = 390, height = 844 } = {}) {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'couchsubs-second-'));
  return new Promise((resolve, reject) => {
    const child = spawn(browser, ['--headless=new', '--disable-gpu', '--disable-background-networking',
      '--no-first-run', '--no-default-browser-check', `--window-size=${width},${height}`, '--lang=tr-TR',
      '--user-data-dir=' + path.join(temp, 'profile'), '--virtual-time-budget=4000', '--dump-dom', url]);
    let out = '';
    child.stdout.on('data', chunk => { out += chunk; });
    const timer = setTimeout(() => { child.kill(); reject(new Error('tarayıcı zamanında bitmedi')); }, 30000);
    child.on('error', reject);
    child.on('close', () => {
      clearTimeout(timer);
      fs.rmSync(temp, { recursive: true, force: true });
      resolve(out);
    });
  });
}

function element(html, id) {
  const match = html.match(new RegExp(`<div id="${id}"([^>]*)>([\\s\\S]*?)</div>`));
  return match ? { attributes: match[1], inner: match[2] } : null;
}

test('ikinci ekran SSE akışındaki altyazıyı konuşan rengiyle büyük yazıyla çizer', { skip: !browser && 'tarayıcı yok' }, async () => {
  const { server, seen, port } = await serve([
    ['style', { fontSize: 46, textColor: 'yellow', bold: false }],
    ['subtitle', { text: 'İlk satır', duration: 15000 }],
    ['subtitle', { text: 'ARTHUR: Gitmeliyiz,\nhemen.', duration: 15000, speakerNames: [{ name: 'ARTHUR', color: '#4FC3F7' }] }],
  ]);
  try {
    const html = await dump(`http://127.0.0.1:${port}/view?k=${KEY}`);
    assert.equal(seen.streams >= 1, true, 'sayfa akışa bağlanmadı');
    assert.equal(seen.streamKey, KEY, 'akış anahtarla açılmalı');
    const line = element(html, 'line');
    assert.ok(line, 'altyazı satırı yok');
    assert.match(line.attributes, /class="on"/);
    // Uygulamanın satır bölmesi birleşir, yalnız konuşanın adı rengini alır, cümle seçilen yazı renginde (sarı).
    assert.match(line.inner, /<span style="color: rgb\(79, 195, 247\);">ARTHUR:<\/span> Gitmeliyiz, hemen\./);
    assert.match(line.attributes, /color: rgb\(255, 225, 53\)/);
    const size = Number((line.attributes.match(/font-size: ([\d.]+)px/) || [])[1]);
    assert.ok(size >= 30, `yazı telefonda büyük olmalı (${size}px)`);
    // Önceki satır üstte soluk durur.
    assert.match(element(html, 'previous').inner, /İlk satır/);
  } finally { server.close(); }
});

test('anahtarsız adres açılmaz', async () => {
  const { server, port } = await serve([]);
  try {
    for (const target of ['/view', '/view?k=yanlis', '/events?viewer=second']) {
      const status = await new Promise(resolve => http.get(`http://127.0.0.1:${port}${target}`, res => { res.resume(); resolve(res.statusCode); }));
      assert.equal(status, 401, target);
    }
  } finally { server.close(); }
});
