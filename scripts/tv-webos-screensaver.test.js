// SPDX-License-Identifier: AGPL-3.0-only
// LG TV (tv-webos/platform.js): oyun sırasında ekran koruyucunun ertelenmesi (#555). tvpower servisi sahte
// PalmServiceBridge ile taklit edilir. Çalıştırma: node --test scripts/tv-webos-screensaver.test.js
'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const code = fs.readFileSync(path.join(__dirname, '..', 'tv-webos', 'platform.js'), 'utf8');
const REGISTER = 'luna://com.webos.service.tvpower/power/registerScreenSaverRequest';
const RESPONSE = 'luna://com.webos.service.tvpower/power/responseScreenSaverRequest';
const FIXED = 'com.couchsubs.tv';

// tvpower taklidi: kayıtlı adlar TV süreci boyunca kalır (önceki açılışlardan gelenler dahil); aynı ad ikinci kez
// kaydedilemez (-3). Ekran koruyucu sorusu canlı kayıtların hepsine gider.
// accepts(name): bu ad kabul edilir mi (false: reddedilir, null: hiç yanıt gelmez). replyFails: TV yanıtı reddeder.
function startTv(registered, options = {}) {
  const calls = [];
  const live = [];
  let timers = [];
  class PalmServiceBridge {
    call(uri, payload) {
      const body = JSON.parse(payload);
      calls.push({ uri, body });
      if (uri === RESPONSE) {
        if (options.replyFails) this.onservicecallback(JSON.stringify({ returnValue: false, errorText: 'invalid client' }));
        return;
      }
      if (uri !== REGISTER) return;
      const verdict = options.accepts ? options.accepts(body.clientName) : true;
      if (verdict === null) return;
      if (verdict === false) {
        this.onservicecallback(JSON.stringify({ returnValue: false, errorCode: -1, errorText: 'not allowed' }));
        return;
      }
      if (registered.has(body.clientName)) {
        this.onservicecallback(JSON.stringify({ returnValue: false, errorCode: -3, errorText: 'already registered' }));
        return;
      }
      registered.add(body.clientName);
      live.push({ bridge: this, clientName: body.clientName });
      this.onservicecallback(JSON.stringify({ returnValue: true, subscribed: true }));
    }
  }
  const window = {};
  const context = {
    window, document: {}, PalmServiceBridge, JSON,
    setTimeout: (fn) => { timers.push(fn); return timers.length; }, clearTimeout: () => {}
  };
  vm.createContext(context);
  vm.runInContext(code, context, { filename: 'platform.js' });
  window.COUCHSUBS_PLATFORM.init();
  return {
    window, calls, live,
    runTimers() { const due = timers; timers = []; due.forEach((fn) => fn()); },
    askScreenSaver(timestamp) {
      live.forEach((c) => c.bridge.onservicecallback(JSON.stringify({ state: 'Active', timestamp })));
    },
    names() { return calls.filter((c) => c.uri === REGISTER).map((c) => c.body.clientName); },
    responses() { return calls.filter((c) => c.uri === RESPONSE).map((c) => c.body); }
  };
}

test('webOS: ekran koruyucu sorusuna kayıt adıyla ack:false yanıtı gider, panelde ertelenen sayısı ve ad görünür', () => {
  const tv = startTv(new Set());
  assert.strictEqual(tv.live.length, 1);
  assert.strictEqual(tv.window.__screenSaverStatus, 'registered (new)');
  tv.askScreenSaver(111);
  tv.askScreenSaver(222);
  const responses = tv.responses();
  assert.strictEqual(responses.length, 2);
  for (const r of responses) {
    assert.strictEqual(r.ack, false);
    assert.strictEqual(r.clientName, tv.live[0].clientName);
  }
  assert.deepStrictEqual(responses.map((r) => r.timestamp), [111, 222]);
  assert.strictEqual(tv.window.__screenSaverStatus, 'deferred 2 (new)');
  // Kabul edilen kayıtta bekleme süresi dolunca başka adla yeniden kaydolunmaz.
  for (let i = 0; i < 5; i++) tv.runTimers();
  assert.strictEqual(tv.names().length, 1);
});

test('webOS: eski açılıştan ölü kayıt kalmışken yeniden açılan uygulama yine kayıt olur (#555)', () => {
  // TV süreci aynı (Hızlı Başlatma+), uygulama kapatılıp açıldı: eski adlar servisin kaydında duruyor.
  const registered = new Set([FIXED]);
  const first = startTv(registered);
  assert.strictEqual(first.live.length, 1);
  assert.notStrictEqual(first.live[0].clientName, FIXED);
  const second = startTv(registered);
  for (let i = 0; i < 5 && second.live.length === 0; i++) second.runTimers();
  assert.strictEqual(second.live.length, 1, 'ikinci açılış da canlı kayıt almalı');
  second.askScreenSaver(333);
  assert.deepStrictEqual(second.responses().map((r) => [r.clientName, r.ack]), [[second.live[0].clientName, false]]);
});

test('webOS: yeni ad reddedilirse eski sabit adla kaydolunur', () => {
  const tv = startTv(new Set(), { accepts: (name) => name === FIXED });
  assert.match(tv.window.__screenSaverStatus, /^denied: not allowed \(new\)$/);
  tv.runTimers();
  assert.deepStrictEqual(tv.names().slice(1), [FIXED]);
  assert.strictEqual(tv.window.__screenSaverStatus, 'registered (fixed)');
  tv.askScreenSaver(444);
  assert.deepStrictEqual(tv.responses().map((r) => [r.clientName, r.ack]), [[FIXED, false]]);
  assert.strictEqual(tv.window.__screenSaverStatus, 'deferred 1 (fixed)');
});

test('webOS: yeni ada hiç yanıt gelmezse eski sabit adla kaydolunur', () => {
  const tv = startTv(new Set(), { accepts: (name) => (name === FIXED ? true : null) });
  assert.strictEqual(tv.live.length, 0);
  tv.runTimers();
  assert.match(tv.window.__screenSaverStatus, /^no reply \(new\)$/);
  tv.runTimers();
  assert.strictEqual(tv.window.__screenSaverStatus, 'registered (fixed)');
  assert.strictEqual(tv.live.length, 1);
});

test('webOS: kayıt reddedilirse başka adla yeniden denenir, sınırsız denenmez', () => {
  const registered = new Set();
  // Her ad önceden alınmış gibi davranan servis: hep -3.
  registered.has = () => true;
  const tv = startTv(registered);
  for (let i = 0; i < 10; i++) tv.runTimers();
  const names = tv.names();
  assert.strictEqual(names.length, 4);
  assert.strictEqual(new Set(names).size, 4);
  assert.strictEqual(names[1], FIXED);
  assert.match(tv.window.__screenSaverStatus, /^denied: already registered \(new\.2\)$/);
});

test('webOS: kabul edilmiş kayıt düşerse yeniden kaydolunur', () => {
  const tv = startTv(new Set());
  tv.live[0].bridge.onservicecallback(JSON.stringify({ returnValue: false, errorText: 'service restarted' }));
  assert.match(tv.window.__screenSaverStatus, /^denied: service restarted \(new\)$/);
  tv.runTimers();
  assert.strictEqual(tv.live.length, 2);
  assert.strictEqual(tv.window.__screenSaverStatus, 'registered (fixed)');
});

test('webOS: TV yanıtı reddederse panelde yazar', () => {
  const tv = startTv(new Set(), { replyFails: true });
  tv.askScreenSaver(555);
  assert.strictEqual(tv.window.__screenSaverStatus, 'reply failed: invalid client @1 (new)');
});

test('webOS: PalmServiceBridge yoksa init hata atmaz', () => {
  const window = {};
  const context = { window, document: {}, JSON, setTimeout: () => 0 };
  vm.createContext(context);
  vm.runInContext(code, context, { filename: 'platform.js' });
  assert.doesNotThrow(() => window.COUCHSUBS_PLATFORM.init());
});
