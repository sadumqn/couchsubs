// SPDX-License-Identifier: AGPL-3.0-only
// GTA 6 telefonu (X, beta.79): telefonun çevirisi mesaj balonlarının üstünde, yerinde durur; altyazı telefonun üstüne
// binmez (tv-webos/app.js avoidPhone), telefonun yanına kayar. "Ekranı çevir"in yerinde balonları ("bubble") balonun
// genişliğinden taşmaz, yazı okunabilir boyda kalır (1080p'de en az 18 piksel), sığmayan Türkçe balonu biraz uzatır. Gerçek kare (testdata/frames/gta6-telefon-sohbet-1.jpg)
// arka planda, gerçek Chromium yerleşimiyle. Ekran görüntüsü: COUCHSUBS_SHOT_DIR verilirse oraya yazılır.
// node --test scripts/tv-phone-bubbles.test.js — tarayıcı yolu: COUCHSUBS_TEST_BROWSER.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { pathToFileURL } = require('node:url');

const root = path.join(__dirname, '..', 'tv-webos');
const frame = path.join(__dirname, '..', 'testdata', 'frames', 'gta6-telefon-sohbet-1.jpg');
const browser = [process.env.COUCHSUBS_TEST_BROWSER, process.env.CHROME_BIN,
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  '/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'].find(p => p && fs.existsSync(p));

// Gerçek karenin balonları (Apple Vision okuması, testdata/frames/ocr/gta6-telefon-sohbet-1.json); renkler balonlardan.
const incoming = { background: '#f6efe8', foreground: '#2a2a2a' };
const outgoing = { background: '#d3dcf4', foreground: '#2a2a2a' };
const bubble = (text, box, surface) => ({ text, box: { left: box[0], top: box[1], right: box[2], bottom: box[3] }, line: 0.034, surface });
const phoneBlocks = [
  bubble('KARAVANIMA! Anladın mı?', [0.62339, 0.26597, 0.74873, 0.3314], incoming),
  bubble('O şeyleri senin için bıraktım', [0.63753, 0.44167, 0.78198, 0.50916], outgoing),
  bubble('Yeni mesaj', [0.64768, 0.59067, 0.75773, 0.62531], incoming),
  bubble('Sağ ol dostum! Başka bir şey bulursan, VE HERHANGİ BİR ŞEY DİYORUM, bana getir', [0.61984, 0.65581, 0.7722, 0.80731], incoming),
];

function slice(app, from, to) {
  const start = app.indexOf(from);
  const end = app.indexOf(to, start);
  assert.ok(start > 0 && end > start, 'TV işlevi bulunamadı: ' + from);
  return app.slice(start, end);
}

function page(script) {
  const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
  const fill = slice(app, '  function fillText(', '\n  }\n') + '\n  }\n';
  const screen = slice(app, '  var screenTimer = null;', '\n  // --- Ek alanlar');
  const regions = slice(app, '  var regionBoxes = {};', '\n  // Konum hem');
  const valid = slice(app, '  function validBox(box)', '\n  //');
  return `<!doctype html><meta charset="utf-8"><style>${fs.readFileSync(path.join(root, 'style.css'), 'utf8')}
    html, body { margin:0; width:1920px; height:1080px; overflow:hidden; background:#000 url('${pathToFileURL(frame).href}') 0 0 / 1920px 1080px no-repeat; }
    #subtitle { position:absolute; left:8%; right:8%; bottom:12%; text-align:center; }
    #result { display:none; }
    #subtitle-text { display:inline-block; font:40px sans-serif; color:#fff; background:rgba(0,0,0,.75); padding:4px 18px; }</style>
    <div id="regions" class="hidden"></div><div id="screen" class="hidden"></div>
    <div id="subtitle" class="hidden"><span id="subtitle-text"></span></div><pre id="result"></pre><script>
    function $(id) { return document.getElementById(id); }
    function hideSubtitle() {}
    var diag = { regions: 0, big: 0 };
    var SIDE_MIN = 0.05;
    ${valid}
    ${fill}
    ${screen}
    ${regions}
    function rect(el) { var r = el.getBoundingClientRect(); return { left: r.left, top: r.top, right: r.right, bottom: r.bottom }; }
    function overlaps(a, b) { return a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom; }
    ${script}
    </script>`;
}

function run(html, extra) {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'couchsubs-phone-test-'));
  try {
    const file = path.join(temp, 'test.html');
    fs.writeFileSync(file, html);
    const result = spawnSync(browser, ['--headless=new', '--disable-gpu', '--disable-background-networking', '--no-first-run',
      '--no-default-browser-check', '--hide-scrollbars', '--force-device-scale-factor=1', '--window-size=1920,1080',
      '--allow-file-access-from-files', ...(process.platform === 'linux' ? ['--no-sandbox'] : []),
      '--user-data-dir=' + path.join(temp, 'profile'), ...extra, pathToFileURL(file).href],
    { encoding: 'utf8', timeout: 30000, windowsHide: true });
    assert.equal(result.status, 0, String(result.error || result.stderr));
    return result.stdout;
  } finally {
    fs.rmSync(temp, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
  }
}

function measure(script) {
  const out = run(page(script), ['--dump-dom']);
  const match = out.match(/<pre id="result">([^<]+)<\/pre>/);
  assert.ok(match, 'Tarayıcı ölçüm üretmedi');
  return JSON.parse(match[1].replace(/&quot;/g, '"').replace(/&amp;/g, '&').replace(/&#39;/g, "'"));
}

function shoot(script, name) {
  const dir = process.env.COUCHSUBS_SHOT_DIR;
  if (!dir) return;
  fs.mkdirSync(dir, { recursive: true });
  run(page(script), ['--virtual-time-budget=2000', '--screenshot=' + path.join(dir, name)]);
}

const subtitleOverPhone = `
  showRegion({ id: 'game-phone', text: 'x', box: { left: 0.6, top: 0.26, right: 0.79, bottom: 0.81 }, blocks: ${JSON.stringify(phoneBlocks)} });
  $('subtitle-text').textContent = 'Telefonu bırak da şu işi bitirelim, Jason. Vaktimiz yok.';
  $('subtitle').style.left = '45%'; $('subtitle').style.right = '0'; $('subtitle').style.bottom = '22%';
  $('subtitle').className = '';
  var before = rect($('subtitle-text'));
  avoidRegions();
  var phone = phoneRect();
  var result = { before: overlaps(before, phone), after: overlaps(rect($('subtitle-text')), phone),
    sub: rect($('subtitle-text')), phone: phone };
  $('result').textContent = JSON.stringify(result);`;

test('altyazı telefonun çevirisinin üstüne binmez, telefonun yanına kayar', { skip: !browser && 'Chromium/Chrome bulunamadı' }, () => {
  const r = measure(subtitleOverPhone);
  assert.equal(r.before, true, 'deneme düzeni: altyazı önce telefonla çakışmalı');
  assert.equal(r.after, false, 'altyazı telefonla çakışıyor: ' + JSON.stringify(r));
  assert.ok(r.sub.left >= 0 && r.sub.right <= 1920 && r.sub.top >= 0 && r.sub.bottom <= 1080, 'altyazı ekran dışında');
  shoot(subtitleOverPhone, 'tv-phone-subtitle.png');
});

// "Ekranı çevir", kartsız (varsayılan): her mesaj kendi balonunun kutusunda (gerçek karenin okuma kutuları), balonun renginde.
const look = { bold: false, condensed: false, align: 'left', upper: false };
const screenBubble = (text, box, surface) => ({ text, box: { left: box[0], top: box[1], right: box[2], bottom: box[3] }, line: 0.033,
  surface: Object.assign({ flat: true }, surface), style: look, bubble: true });
const bubbles = [
  screenBubble('KARAVANIMA! Anladın mı?', [0.62339, 0.26597, 0.74873, 0.3314], incoming),
  screenBubble('Donnie\'nin Evi', [0.64826, 0.35917, 0.77326, 0.38243], incoming),
  screenBubble('O şeyleri senin için bıraktım', [0.63753, 0.44167, 0.78198, 0.50916], outgoing),
  screenBubble('Yeni mesaj', [0.64768, 0.59067, 0.75773, 0.62531], incoming),
  screenBubble('Sağ ol dostum! Başka bir şey bulursan, VE HERHANGİ BİR ŞEY DİYORUM, bana getir', [0.61984, 0.65581, 0.7722, 0.80731], incoming),
];
const inPlace = `
  showScreen(${JSON.stringify(bubbles)}, 20000);
  var list = Array.prototype.slice.call($('screen').children).map(function (el, i) {
    var r = rect(el), b = ${JSON.stringify(bubbles)}[i].box;
    return { text: el.textContent, font: parseFloat(getComputedStyle(el).fontSize), wide: el.scrollWidth > el.clientWidth + 1,
      left: r.left, right: r.right, top: r.top, bottom: r.bottom, boxBottom: b.bottom * 1080, boxRight: b.right * 1920,
      background: getComputedStyle(el).backgroundColor, bubble: el.className.indexOf('bubble') >= 0 };
  });
  $('result').textContent = JSON.stringify(list);`;

test('"Ekranı çevir" balonları yerinde: taşmaz, okunur boyda, balon rengiyle', { skip: !browser && 'Chromium/Chrome bulunamadı' }, () => {
  const list = measure(inPlace);
  assert.equal(list.length, bubbles.length);
  for (const [i, el] of list.entries()) {
    assert.equal(el.bubble, true, el.text);
    assert.equal(el.wide, false, 'yatayda taşıyor: ' + el.text);
    assert.ok(el.right <= el.boxRight + 0.004 * 1920 + 1, 'balonun sağından taşıyor: ' + el.text);
    assert.ok(el.font >= 18, 'yazı okunamayacak kadar küçük (' + el.font + ' px): ' + el.text);
    // Sığmayan Türkçe balonu biraz uzatır, sonraki balonun üstüne binmez.
    if (i + 1 < list.length) assert.ok(el.bottom <= list[i + 1].top + 1, 'sonraki balonun üstüne biniyor: ' + el.text);
    assert.ok(el.bottom - el.boxBottom <= 0.06 * 1080, 'balon çok uzadı: ' + el.text);
  }
  assert.equal(list[2].background, 'rgb(211, 220, 244)', 'giden balon kendi renginde');
  assert.equal(list[0].background, 'rgb(246, 239, 232)', 'gelen balon kendi renginde');
  shoot(inPlace, 'tv-phone-bubbles.png');
});

// Yanda Panel (varsayılan; X'te monitörle oynayan kullanıcı: balonların üstündeki çeviri kayıyor, küçük, kimin ne dediği
// belli olmuyor): telefon sağdaysa panel solunda, yuvarlak köşeli yarı saydam koyu kartta; üstte kişinin adı, karşı
// taraf solda krem, oyuncu sağda amber balon; sığmayan eski mesajlar düşer, son mesaj görünür kalır.
const cardStyle = { background: '#141518', foreground: '#F3EEE4' };
const part = (panel, text, box, surface) => ({ text, box: { left: box[0], top: box[1], right: box[2], bottom: box[3] }, line: 0.022,
  surface: Object.assign({ flat: true }, surface), style: look, panel });
const panelBlocks = (count) => [
  part('card', ' ', [0.31, 0.26, 0.592, 0.81], cardStyle),
  part('title', 'Lucia', [0.32, 0.27, 0.58, 0.30], cardStyle),
].concat(Array.from({ length: count }, (_, i) => i % 2
  ? part('mine', 'O şeyleri senin için bıraktım ' + i, [0.40, 0.32 + i * 0.01, 0.58, 0.33 + i * 0.01], { background: '#F5B83D', foreground: '#17181B' })
  : part('theirs', 'Sağ ol dostum! Başka bir şey bulursan bana getir ' + i, [0.32, 0.32 + i * 0.01, 0.52, 0.33 + i * 0.01], { background: '#F3EEE4', foreground: '#17181B' })));
const sidePanel = (count) => `
  showRegion({ id: 'game-phone', text: 'x', box: { left: 0.31, top: 0.26, right: 0.79, bottom: 0.81 }, blocks: ${JSON.stringify(panelBlocks(count))} });
  var panel = document.querySelector('.phone-panel');
  var style = getComputedStyle(panel), messages = panel.querySelector('.panel-messages');
  var rows = Array.prototype.slice.call(panel.querySelectorAll('.panel-row')).map(function (row) {
    var bubble = row.querySelector('.panel-bubble');
    return { text: bubble.textContent, side: row.className, font: parseFloat(getComputedStyle(bubble).fontSize),
      background: getComputedStyle(bubble).backgroundColor, box: rect(bubble) };
  });
  $('result').textContent = JSON.stringify({ panel: rect(panel), radius: parseFloat(style.borderTopLeftRadius),
    background: style.backgroundColor, title: panel.querySelector('.panel-title').textContent, rows: rows,
    list: rect(messages), couch: !!panel.querySelector('.panel-couch'), loose: document.querySelectorAll('#regions .item').length });`;

test('Yanda Panel: sohbet telefonun yanında, kim ne dedi belli, son mesaj görünür', { skip: !browser && 'Chromium/Chrome bulunamadı' }, () => {
  const r = measure(sidePanel(4));
  assert.equal(r.loose, 0, 'panel parçaları ayrıca yerinde çizilmez');
  assert.ok(r.panel.right <= 0.6 * 1920, 'panel telefonun üstüne biniyor: ' + JSON.stringify(r.panel));
  assert.ok(r.radius >= 16, 'köşe yuvarlak değil');
  assert.match(r.background, /rgba\(20, 21, 24, 0\.88\)/, 'zemin yarı saydam koyu değil: ' + r.background);
  assert.equal(r.title, 'Lucia');
  assert.equal(r.couch, true);
  assert.equal(r.rows.length, 4);
  const theirs = r.rows.filter(row => row.side.indexOf('theirs') >= 0), mine = r.rows.filter(row => row.side.indexOf('mine') >= 0);
  assert.ok(theirs.every(t => t.box.left < mine[0].box.left), 'karşı taraf solda, oyuncu sağda değil');
  assert.ok(mine.every(m => m.box.right > r.panel.right - 0.03 * 1920), 'oyuncunun balonu sağa yaslı değil');
  assert.equal(mine[0].background, 'rgb(245, 184, 61)', 'oyuncunun balonu amber');
  assert.equal(theirs[0].background, 'rgb(243, 238, 228)', 'karşı tarafın balonu krem');
  for (let i = 0; i + 1 < r.rows.length; i++) assert.ok(r.rows[i].box.bottom <= r.rows[i + 1].box.top + 1, 'balonlar üst üste');
  assert.ok(r.rows.every(row => row.font >= 18), 'yazı okunamayacak kadar küçük');
  shoot(sidePanel(4), 'tv-phone-panel.png');

  const full = measure(sidePanel(30));
  assert.ok(full.rows.length < 30 && full.rows.length >= 3, 'sığmayan eski mesajlar düşmedi: ' + full.rows.length);
  assert.ok(full.rows[full.rows.length - 1].text.endsWith(' 29'), 'son mesaj görünmüyor');
  assert.ok(full.rows[full.rows.length - 1].box.bottom <= full.list.bottom + 1, 'son mesaj panelden taşıyor');
});

// X (22 Kas, GTA 6 telefonu: "yazılar sürekli oynuyor"): TV uygulaması 0.9.78 telefonun gönderisini yerinde günceller. Aynı
// gönderi hiçbir şeyi yeniden çizmez; yeni mesaj gelince panel ve mevcut balonlar aynı DOM düğümleri olarak kalır, yeni
// mesaj alta eklenir; balonların üstündeki çeviride de aynı yazının kutusu korunur, yalnız yeri güncellenir.
const inPlaceUpdate = `
  var blocks = ${JSON.stringify(panelBlocks(3))};
  var region = { id: 'game-phone', text: 'x', box: { left: 0.31, top: 0.26, right: 0.79, bottom: 0.81 }, blocks: blocks };
  showRegion(region);
  var panel = document.querySelector('.phone-panel');
  var rows = Array.prototype.slice.call(panel.querySelectorAll('.panel-row'));
  rows.forEach(function (row, i) { row.couchsubsMark = i; });
  showRegion(JSON.parse(JSON.stringify(region)));
  var same = document.querySelector('.phone-panel') === panel && panel.querySelectorAll('.panel-row').length === 3 &&
    Array.prototype.every.call(panel.querySelectorAll('.panel-row'), function (row, i) { return row.couchsubsMark === i; });
  var more = JSON.parse(JSON.stringify(blocks));
  more.push({ text: 'Yeni mesaj', box: { left: 0.32, top: 0.40, right: 0.5, bottom: 0.41 }, line: 0.022,
    surface: { flat: true, background: '#F3EEE4', foreground: '#17181B' }, panel: 'theirs' });
  // Akışla çizilen mesajların kutusu biraz oynasa da satırlar yeniden yaratılmaz.
  more[2].box.top += 0.003; more[2].box.bottom += 0.003;
  showRegion({ id: 'game-phone', text: 'x', box: region.box, blocks: more });
  var after = Array.prototype.slice.call(document.querySelectorAll('.phone-panel .panel-row'));
  var appended = document.querySelector('.phone-panel') === panel && after.length === 4 &&
    after.slice(0, 3).every(function (row, i) { return row.couchsubsMark === i; }) && after[3].couchsubsMark === undefined &&
    after[3].textContent === 'Yeni mesaj';
  hideRegions();
  var bubble = { text: 'Yarın buluşalım.', box: { left: 0.62, top: 0.40, right: 0.75, bottom: 0.44 }, line: 0.03,
    surface: { background: '#F6EFE8', foreground: '#2A2A2A' } };
  showRegion({ id: 'game-phone', text: 'x', box: bubble.box, blocks: [bubble] });
  var first = document.querySelector('#regions .item');
  var moved = JSON.parse(JSON.stringify(bubble));
  moved.box.top = 0.30; moved.box.bottom = 0.34;
  showRegion({ id: 'game-phone', text: 'x', box: moved.box, blocks: [moved] });
  var kept = document.querySelectorAll('#regions .item').length === 1 && document.querySelector('#regions .item') === first &&
    Math.abs(parseFloat(first.style.top) - 30) < 0.5;
  $('result').textContent = JSON.stringify({ same: same, appended: appended, kept: kept });`;

test('telefonun gönderisi yerinde güncellenir: aynı gönderi yeniden çizilmez, yeni mesaj alta eklenir', { skip: !browser && 'Chromium/Chrome bulunamadı' }, () => {
  const r = measure(inPlaceUpdate);
  assert.equal(r.same, true, 'aynı gönderi paneli yeniden yarattı');
  assert.equal(r.appended, true, 'yeni mesajda mevcut balonlar yeniden yaratıldı ya da yeni mesaj alta eklenmedi');
  assert.equal(r.kept, true, 'balonun kutusu yeniden yaratıldı ya da yeri güncellenmedi');
});
