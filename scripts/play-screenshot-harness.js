// SPDX-License-Identifier: AGPL-3.0-only
// Google Play ekran görüntüleri için Android TV köprüsünün (window.AndroidTV) ve bilgisayar bağlantısının taklidi.
// scripts/play-screenshots.sh bunu TV sayfasının (tv-webos + tv-android/platform.js) önüne koyar; sayfa olduğu gibi çalışır.
// Adres: index.html?lang=tr|en&state=waiting|demo|stacked|panel
(function () {
  'use strict';

  var query = {};
  location.search.slice(1).split('&').forEach(function (pair) {
    var parts = pair.split('=');
    if (parts[0]) query[parts[0]] = decodeURIComponent(parts[1] || '');
  });
  var state = query.state || 'waiting';
  var connected = state === 'stacked' || state === 'panel';

  Object.defineProperty(navigator, 'language', { get: function () { return query.lang || 'en'; } });
  try { localStorage.clear(); } catch (e) { /* yok */ }

  window.AndroidTV = {
    isOverlay: function () { return false; },
    appVersion: function () { return '0.9.12'; },
    launchParams: function () { return connected ? '{"server":"http://192.168.1.20:8787","hdmi":1}' : ''; },
    showHdmi: function () { setTimeout(function () { window.__onHdmiStatus('playing'); }, 10); },
    consolePort: function () { return 1; },
    localAddress: function () { return ''; },
    exit: function () {},
    setDisplayMode: function () {}
  };

  // Bilgisayardaki CouchSubs'ın gönderdiği olaylar (SSE). Metinler demo satırlarıyla aynı türden kurgu cümlelerdir.
  var LINES = ['MİRA: Kapı daha fazla dayanmayacak!', 'Yakın dur, ilerideki yol tehlikeli.'];
  function FakeSource(url) {
    var self = this;
    this.url = url;
    this.readyState = 0;
    this.listeners = {};
    setTimeout(function () {
      self.readyState = 1;
      if (self.onopen) self.onopen({});
      self.emit('open', {});
      self.emit('style', { data: '{}' });
      // Hızlı konuşma: ikinci satır 1,5 sn içinde gelir, önceki üstte soluk kalır. Görüntü bu sırada alınır
      // (play-screenshots.sh'teki --virtual-time-budget sonunda; önceki satır ikinciden 1,5 sn sonra kalkar).
      if (state === 'stacked') {
        setTimeout(function () {
          self.emit('subtitle', { data: JSON.stringify({ text: LINES[0], duration: 8000 }) });
        }, 1200);
        setTimeout(function () {
          self.emit('subtitle', { data: JSON.stringify({ text: LINES[1], duration: 8000 }) });
        }, 1700);
      }
      if (state === 'panel') self.emit('subtitle', { data: JSON.stringify({ text: LINES[1], duration: 1 }) });
    }, 50);
  }
  FakeSource.prototype.addEventListener = function (name, fn) { (this.listeners[name] = this.listeners[name] || []).push(fn); };
  FakeSource.prototype.emit = function (name, event) { (this.listeners[name] || []).forEach(function (fn) { fn(event); }); };
  FakeSource.prototype.close = function () { this.readyState = 2; };
  window.EventSource = FakeSource;

  function key(code) {
    var event = new Event('keydown', { cancelable: true });
    event.keyCode = code;
    document.dispatchEvent(event);
  }

  window.addEventListener('load', function () {
    setTimeout(function () {
      if (state === 'demo') key(406);
      // Bağlanınca panel birkaç saniye kendiliğinden açık kalır (panel durumu bunu gösterir); altyazı görüntüsünde kapatılır.
      if (state === 'stacked') key(404);
    }, 300);
  });
})();
