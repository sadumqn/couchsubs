// SPDX-License-Identifier: AGPL-3.0-only
// #1055 (LG OLED C4): çeviri sırasında ekran kararıp "HDR" yazısıyla geri geliyordu. Aynı HDMI girişini yeniden açmak
// <video>'yu bırakıp yeniden kurar (webOS platform.showHdmi); TV uygulaması 0.9.80'den beri bilgisayarın/telefonun
// bildirdiği giriş (açılış parametresi `hdmi`, stil `hdmiInput`) zaten gösterilen girişse görüntüye dokunulmaz. Kumandayla
// seçim ve farklı giriş eskisi gibi açılır. Sayfa app.js'i ortak kullanır (scripts/tv-live-page.js).
// Çalıştırma: node --test --test-force-exit scripts/tv-hdmi-reselect.test.js (sayfanın yeniden bağlanma zamanlayıcıları
// süreci açık tutar)
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { startPage } = require('./tv-live-page');

// Anahtarsız (auth 0) en küçük CouchSubs sunucusu: sayfa ağda sunucu aramaz, doğrudan akışa bağlanır.
function couchsubs() {
  const streams = [];
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://x');
    if (url.pathname === '/hello') return res.end(JSON.stringify({ app: 'couchsubs', auth: 0, id: 'hdmi-test', tvs: streams.length }));
    if (url.pathname === '/events') {
      res.writeHead(200, { 'Content-Type': 'text/event-stream; charset=utf-8' });
      res.write('retry: 2000\n\n');
      streams.push(res);
      req.on('close', () => streams.splice(streams.indexOf(res), 1));
      return undefined;
    }
    res.statusCode = 404;
    return res.end();
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve({
    address: 'http://127.0.0.1:' + server.address().port,
    tvs: () => streams.length,
    close() { for (const res of streams) res.destroy(); server.close(); }
  })));
}

async function until(condition, what, ms = 5000) {
  const deadline = Date.now() + ms;
  while (!condition()) {
    if (Date.now() > deadline) throw new Error(what + ' zamanında olmadı');
    await new Promise((r) => setTimeout(r, 20));
  }
}

test('bilgisayarın bildirdiği giriş zaten açıksa görüntü yeniden kurulmaz; başka giriş açılır', async () => {
  const computer = await couchsubs();
  const page = startPage({ params: { server: computer.address }, port: 2 });
  try {
    await until(() => computer.tvs() === 1, 'akışa bağlanma');
    const before = page.shownPorts();
    assert.deepEqual(before.slice(-1), [2]);
    // Bekçi uygulamayı aynı girişle yeniden açtı (her yeniden açışta aynı değer): görüntüye dokunulmaz.
    for (let i = 0; i < 5; i++) page.relaunch({ server: computer.address, hdmi: 2 });
    assert.equal(page.shownPorts().length, before.length);
    assert.equal(page.stored('hdmi'), '2');
    // Başka giriş bildirildi: o giriş açılır.
    page.relaunch({ server: computer.address, hdmi: 3 });
    assert.deepEqual(page.shownPorts().slice(before.length), [3]);
  } finally {
    page.close();
    computer.close();
  }
});
