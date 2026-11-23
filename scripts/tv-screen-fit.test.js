// SPDX-License-Identifier: AGPL-3.0-only
// "Ekranı çevir" TV çiziminin yerleşim ölçütü, gerçek GTA 6 menü/görev karelerinden (testdata/frames/ocr/screen-fit-items.json;
// core ScreenFitTests SCREEN_FIT_OUT ile yazar). Gerçek Chromium yerleşimiyle her çeviri kutusu ölçülür:
//  - konum sapması: çizilen kutunun üst/alt kenarı ve hizasındaki yatay kenarı özgün yazının kutusundan en çok satır
//    yüksekliğinin %10'u kadar uzak (kutunun kendi kenar payı hariç);
//  - yazı boyu: çizilen yazı boyu / özgün satırın yazı boyu 1,0 (±%5); küçültme yok;
//  - kumanda simgesi ve görev fotoğrafı (frames.json → screen.clear) hiç örtülmez;
//  - kutular birbirine binmez, yazı kendi kutusundan taşmaz (eski Chromium dönüşümü kaydırma payına saymıyordu).
// Ölçüler 1080p, 720p ve 4K ekranlarda aynı olmalı.
// node --test scripts/tv-screen-fit.test.js — tarayıcı yolu: COUCHSUBS_TEST_BROWSER.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { pathToFileURL } = require('node:url');

const root = path.join(__dirname, '..', 'tv-webos');
const browser = [process.env.COUCHSUBS_TEST_BROWSER, process.env.CHROME_BIN,
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  '/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'].find(p => p && fs.existsSync(p));
const frames = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'testdata', 'frames', 'ocr', 'screen-fit-items.json'), 'utf8'));

function render(width, height, zoom, shot) {
  const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
  const slice = (from, to) => {
    const start = app.indexOf(from);
    const end = app.indexOf(to, start);
    assert.ok(start > 0 && end > start, 'TV işlevi bulunamadı: ' + from);
    return app.slice(start, end);
  };
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'couchsubs-screen-fit-'));
  try {
    const html = `<!doctype html><meta charset="utf-8"><style>${fs.readFileSync(path.join(root, 'style.css'), 'utf8')}</style>
      ${shot ? `<style>body{margin:0}</style><img style="position:absolute;left:0;top:0;width:${width}px;height:${height}px" src="${pathToFileURL(path.join(__dirname, '..', 'testdata', 'frames', shot.file)).href}">` : ''}
      <div id="regions" class="hidden"></div><div id="screen"></div><pre id="result" ${shot ? 'hidden' : ''}></pre><script>
      // Pencere çerçevesi görüntü alanını kısaltabiliyor (macOS'ta 1080 yerine 993): ekran ölçüsü sabitlenir.
      Object.defineProperty(window, 'innerWidth', { value: ${width} });
      Object.defineProperty(window, 'innerHeight', { value: ${height} });
      window.COUCHSUBS_ZOOM = ${zoom || 1};
      function $(id) { return document.getElementById(id); }
      function hideSubtitle() {}
      function resolveLayers() {}
      var diag = { regions: 0, big: 0 };
      var setApart = true;
      ${slice('  function validBox(box)', '\n  //')}
      ${slice('  function fillText(el, text, icons)', '\n  //')}
      ${slice('  var screenTimer = null;', '\n  // --- Ek alanlar')}
      var frames = ${JSON.stringify(shot ? frames.filter(f => f.id === shot.id) : frames)};
      var result = [];
      var W = (window.innerWidth || 1920) / (window.COUCHSUBS_ZOOM || 1), H = (window.innerHeight || 1080) / (window.COUCHSUBS_ZOOM || 1);
      frames.forEach(function (frame) {
        showScreen(frame.items, 20000);
        var host = $('screen');
        var drawn = Array.from(host.querySelectorAll('.item')).map(function (el) {
          var b = el.getBoundingClientRect(), z = window.COUCHSUBS_ZOOM || 1, cs = getComputedStyle(el);
          var parts = Array.from(el.querySelectorAll('.cover-part')).map(function (p) {
            var r = p.getBoundingClientRect();
            return { left: r.left / z / W, top: r.top / z / H, right: r.right / z / W, bottom: r.bottom / z / H };
          });
          return { text: el.textContent, font: parseFloat(getComputedStyle(el).fontSize),
            left: b.left / z / W, top: b.top / z / H, right: b.right / z / W, bottom: b.bottom / z / H, parts: parts,
            // Yazının alanı (kenar payı hariç): özgün yazının kutusuyla karşılaştırılır.
            area: { left: (b.left + parseFloat(cs.paddingLeft)) / z / W, top: (b.top + parseFloat(cs.paddingTop)) / z / H,
              right: (b.right - parseFloat(cs.paddingRight)) / z / W, bottom: (b.bottom - parseFloat(cs.paddingBottom)) / z / H },
            // İki piksel pay: kenar payının kesirli pikselleri iki yanda yuvarlanır.
            scroll: el.scrollWidth > el.clientWidth + 2 || el.scrollHeight > el.clientHeight + 2,
            dims: [el.scrollWidth, el.clientWidth, el.scrollHeight, el.clientHeight] };
        });
        result.push({ id: frame.id, drawn: drawn, H: H });
      });
      $('result').textContent = btoa(unescape(encodeURIComponent(JSON.stringify(result))));
      </script>`;
    const file = path.join(temp, 'fit.html');
    fs.writeFileSync(file, html);
    const run = spawnSync(browser, ['--headless=new', '--disable-gpu', '--disable-background-networking',
      '--no-first-run', '--no-default-browser-check', '--hide-scrollbars', '--force-device-scale-factor=1', '--window-size=' + width + ',' + (height + 200),
      ...(process.platform === 'linux' ? ['--no-sandbox'] : []),
      '--user-data-dir=' + path.join(temp, 'profile'), ...(shot ? ['--screenshot=' + shot.out] : ['--dump-dom']), pathToFileURL(file).href],
      { encoding: 'utf8', timeout: 30000, maxBuffer: 4 * 1024 * 1024, windowsHide: true });
    assert.equal(run.status, 0, String(run.error || run.stderr));
    if (shot) return null;
    const match = run.stdout.match(/<pre id="result">([A-Za-z0-9+/=]+)<\/pre>/);
    assert.ok(match, 'Tarayıcı ölçüm üretmedi: ' + run.stdout.slice(-1000));
    return JSON.parse(Buffer.from(match[1], 'base64').toString('utf8'));
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
  }
}

// En az bir piksel (1080p) üst üste mi; simge alanları elle dört basamakla yazıldı.
const intersects = (a, b) => Math.min(a.right, b.right) > Math.max(a.left, b.left) + 1 / 1920
  && Math.min(a.bottom, b.bottom) > Math.max(a.top, b.top) + 1 / 1080;

// Kare başına ölçüler: en büyük konum sapması (satır yüksekliğine oranla), en küçük/en büyük yazı boyu oranı, örtülen
// simge/fotoğraf sayısı, çakışma sayısı.
function measure(rendered) {
  return rendered.map((frame, f) => {
    const source = frames[f];
    const out = { id: frame.id, shift: 0, minRatio: Infinity, maxRatio: 0, covered: [], overlaps: 0, spill: frame.drawn.filter(el => el.scroll).map(el => el.text + " " + el.dims.join("/")) };
    frame.drawn.forEach((el, i) => {
      const item = source.items[i];
      const box = item.box, line = item.line;
      const nominal = Math.round(line * frame.H * 0.95);
      const ratio = el.font / nominal;
      out.minRatio = Math.min(out.minRatio, ratio);
      out.maxRatio = Math.max(out.maxRatio, ratio);
      const align = (item.style && item.style.align) || 'left';
      // Konum sapması: yazının alanının üst/alt kenarı ve hizasındaki yatay kenarı (ortalıysa ortası), satır yüksekliğine
      // oranla (yatay fark ekranın en-boy oranıyla satır birimine çevrilir).
      const t = el.area, aspect = 16 / 9;
      const edges = [Math.abs(t.top - box.top), Math.abs(t.bottom - box.bottom)];
      if (align === 'left') edges.push(Math.abs(t.left - box.left) * aspect);
      else if (align === 'right') edges.push(Math.abs(t.right - box.right) * aspect);
      else edges.push(Math.abs((t.left + t.right) / 2 - (box.left + box.right) / 2) * aspect);
      out.shift = Math.max(out.shift, Math.max(...edges) / line);
      if (process.env.SCREEN_FIT_ITEMS) {
        const f3 = v => v.toFixed(3);
        console.log(`  ${frame.id} «${el.text}» yazı ${el.font}/${nominal} kutu ${[box.left, box.top, box.right, box.bottom].map(f3)}`
          + ` çizilen ${[el.left, el.top, el.right, el.bottom].map(f3)} sapma ${(Math.max(...edges) / line).toFixed(2)}`);
      }
      const pieces = el.parts.length ? el.parts : [el];
      for (const zone of source.clear) {
        const z = { left: zone[0], top: zone[1], right: zone[2], bottom: zone[3] };
        if (pieces.some(p => intersects(p, z))) out.covered.push(el.text);
      }
    });
    for (let i = 0; i < frame.drawn.length; i++)
      for (let j = i + 1; j < frame.drawn.length; j++)
        if (intersects(frame.drawn[i], frame.drawn[j])) out.overlaps++;
    return out;
  });
}

// SCREEN_FIT_SHOT=<klasör>: her karenin TV çizimi karenin üstünde ekran görüntüsü olarak kaydedilir (gözle denetim).
if (process.env.SCREEN_FIT_SHOT && browser) {
  for (const frame of frames) {
    render(1920, 1080, 1, { id: frame.id, file: frame.id + '.jpg', out: path.join(process.env.SCREEN_FIT_SHOT, frame.id + '.png') });
  }
}

const screens = [[1920, 1080, 1], [1280, 720, 1], [3840, 2160, 1]];

test('ekranı çevir: çeviri özgün yazının yerinde, boyunda; simge örtmez, kutular binmez', { skip: !browser && 'Chromium bulunamadı' }, () => {
  const failures = [];
  for (const [width, height, zoom] of screens) {
    for (const m of measure(render(width, height, zoom))) {
      if (process.env.SCREEN_FIT_REPORT) console.log(width + 'x' + height, JSON.stringify(m));
      const at = `${width}x${height} ${m.id}`;
      if (m.shift > 0.10) failures.push(`${at}: konum sapması ${m.shift.toFixed(2)} satır`);
      if (m.minRatio < 0.95 || m.maxRatio > 1.05) failures.push(`${at}: yazı boyu oranı ${m.minRatio.toFixed(2)}–${m.maxRatio.toFixed(2)}`);
      if (m.covered.length) failures.push(`${at}: simge/fotoğraf örtülüyor: ${m.covered.join(', ')}`);
      if (m.overlaps) failures.push(`${at}: ${m.overlaps} kutu üst üste`);
      if (m.spill.length) failures.push(`${at}: kutusundan taşan yazı: ${m.spill.join(', ')}`);
    }
  }
  assert.deepEqual(failures, []);
});
