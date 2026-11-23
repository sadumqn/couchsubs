// SPDX-License-Identifier: AGPL-3.0-only
// "Üstünü örtsün" örtüsünün yeri (tv-webos/app.js). Android TV katmanında HDMI'yı TV'nin kendi ekranı büyüterek
// (overscan) çizer; örtü İngilizce satırdan dar kalıp yazı yanlardan görünüyordu (#473).
// Çalıştırma: node --test scripts/tv-cover.test.js
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const app = fs.readFileSync(path.join(__dirname, '..', 'tv-webos', 'app.js'), 'utf8');
const start = app.indexOf('  var COVER_PAD');
const end = app.indexOf('  function placeCover(');
assert.ok(start > 0 && end > start, 'örtü işlevleri bulunamadı');

function load(bodyClass) {
  const context = { document: { body: { className: bodyClass } } };
  vm.createContext(context);
  vm.runInContext(app.slice(start, end) + '\nthis.api = { screenBox, coverBounds, isOverlay };', context);
  return context.api;
}

// TV resmi %5 büyütünce satırın ekrandaki yeri.
function zoomed(box, zoom) {
  const at = (v) => 0.5 + (v - 0.5) * zoom;
  return { left: at(box.left), top: at(box.top), right: at(box.right), bottom: at(box.bottom) };
}

function covers(outer, inner) {
  return outer.left <= inner.left && outer.top <= inner.top && outer.right >= inner.right && outer.bottom >= inner.bottom;
}

const line = { left: 0.2, top: 0.86, right: 0.8, bottom: 0.92 };

test('uygulama içinde örtü satırın kutusu ve payı kadardır', () => {
  const api = load('band');
  assert.equal(api.isOverlay(), false);
  const bounds = api.coverBounds(api.screenBox(line, false), false);
  assert.ok(Math.abs(bounds.left - 0.188) < 1e-9 && Math.abs(bounds.right - 0.812) < 1e-9);
});

test('katmanda TV resmi büyütse de örtü İngilizce satırı kaplar (#473)', () => {
  const api = load('band overlay');
  assert.equal(api.isOverlay(), true);
  const bounds = api.coverBounds(api.screenBox(line, true), true);
  assert.ok(covers(bounds, zoomed(line, 1.05)), JSON.stringify(bounds));
  // Eski hesap büyütülmüş satırı kaplamıyordu.
  const old = load('band').coverBounds(line, false);
  assert.ok(!covers(old, zoomed(line, 1.05)));
});

test('katmanda TV resmi büyütmese de örtü satırı yine kaplar', () => {
  const api = load('overlay');
  for (const box of [line, { left: 0.05, top: 0.05, right: 0.4, bottom: 0.1 }, { left: 0.45, top: 0.48, right: 0.55, bottom: 0.52 }]) {
    const bounds = api.coverBounds(api.screenBox(box, true), true);
    assert.ok(covers(bounds, box), JSON.stringify({ box, bounds }));
  }
});
