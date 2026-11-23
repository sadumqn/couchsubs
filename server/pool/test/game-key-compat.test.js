// SPDX-License-Identifier: AGPL-3.0-only
// Existing catalog entries and alias variants must retain their original package keys.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { gameKey } from "../src/games.js";

// Pre-fix normalizer, retained only as a compatibility oracle for known titles.
const ALIASES = [
  ["grand theft auto", "gta"], ["call of duty", "cod"], ["red dead redemption", "rdr"],
  ["ea sports fc", "fc"], ["ea sports", ""],
];
const ROMAN = { ii: "2", iii: "3", iv: "4", v: "5", vi: "6", vii: "7", viii: "8",
  ix: "9", x: "10", xi: "11", xii: "12", xiii: "13", xiv: "14", xv: "15", xvi: "16" };

function legacyGameKey(value) {
  let t = value.replace(/[™®©]/g, " ").normalize("NFKD").toLowerCase().replace(/\p{M}/gu, "");
  t = t.replace(/['’\x60]/g, "").replace(/&/g, " and ").replace(/ı/g, "i");
  t = t.replace(/[^\p{L}\p{N}]+/gu, " ");
  t = t.replace(/(\p{L})(\p{N})/gu, "$1 $2").replace(/(\p{N})(\p{L})/gu, "$1 $2");
  let words = t.split(" ").filter(Boolean).map((w) => ROMAN[w] ?? w);
  if (words[0] === "the" && words.length > 1) words = words.slice(1);
  let joined = " " + words.join(" ") + " ";
  for (const [long, short] of ALIASES) {
    joined = joined.split(" " + long + " ").join(short ? " " + short + " " : " ");
  }
  return joined.replace(/\s+/g, " ").trim().slice(0, 80).trim();
}

const catalogFiles = [
  { path: "../../../core/Sources/CouchSubsCore/GameSense.swift",
    start: /public static let popular:\s*\[String\]\s*=\s*\[/, end: /\n\s*\]/ },
  { path: "../../../windows/src/CouchSubs.Core/GameSense.cs",
    start: /public static readonly IReadOnlyList<string> Popular\s*=\s*\[/, end: /\n\s*\];/ },
  { path: "../../../couchsubs-android/app/src/main/java/com/couchsubs/mobile/core/GameSense.kt",
    start: /val POPULAR\s*=\s*listOf\(/, end: /\n\s*\)/ },
];

function catalogTitles(file) {
  const source = readFileSync(new URL(file.path, import.meta.url), "utf8");
  const start = file.start.exec(source);
  assert.ok(start, "Missing catalog marker in " + file.path);
  const tail = source.slice(start.index + start[0].length);
  const end = file.end.exec(tail);
  assert.ok(end, "Missing catalog end marker in " + file.path);
  const literals = tail.slice(0, end.index);
  return [...literals.matchAll(/"(?:\\.|[^"\\])*"/g)].map((m) => JSON.parse(m[0]));
}

test("catalog and established alias titles preserve their old package keys", () => {
  const names = new Set([
    ...catalogFiles.flatMap(catalogTitles),
    "Grand Theft Auto V Enhanced",
    "GTA V Premium Edition",
    "Final Fantasy X HD",
    "GTA V Premium Edition (Steam)",
    "Red Dead Redemption II Ultimate Edition",
    "EA SPORTS FC 26", "EA FC 26", "Call of Duty: Modern Warfare III",
  ]);
  assert.ok(names.size >= 50, "Catalog title coverage unexpectedly shrank");
  for (const name of names) {
    assert.equal(gameKey(name), legacyGameKey(name), "Changed existing game key: " + name);
  }
});

test("literal franchise titles stay distinct, including numbered/remastered variants", () => {
  const expected = new Map([
    ["Mega Man X", "mega man x"],
    ["Mega Man X2", "mega man x 2"],
    ["Mega Man X HD", "mega man x hd"],
    ["Mega Man 10", "mega man 10"],
    ["X-Men", "x men"],
    ["X-Men Origins: Wolverine", "x men origins wolverine"],
    ["V-Rally", "v rally"],
    ["V-Rally 4", "v rally 4"],
  ]);
  for (const [name, key] of expected) {
    assert.equal(gameKey(name), key, name);
  }
  assert.notEqual(gameKey("Mega Man X HD"), gameKey("Mega Man 10 HD"));
});
