// SPDX-License-Identifier: AGPL-3.0-only
import { execFileSync } from "node:child_process";
import { test } from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { mkdtempSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { gzipSync } from "node:zlib";

const script = fileURLToPath(new URL("../scripts/build-known.mjs", import.meta.url));
const defaultPacks = fileURLToPath(new URL("../../../core/Sources/CouchSubsCore/Resources/packs/", import.meta.url));

// Paketler depoda değil (özel R2, scripts/fetch-packs.py); inmemişse depo klasörü testi atlanır.
const havePacks = readdirSync(defaultPacks).some((name) => name.endsWith(".json.gz"));

test("build-known uses its default pack directory on all platforms", { skip: !havePacks && "gerçek paketler yok" }, () => {
  const options = { stdio: ["ignore", "pipe", "ignore"], maxBuffer: 16 * 1024 * 1024 };
  const explicit = execFileSync(process.execPath, [script, defaultPacks], options);
  const inferred = execFileSync(process.execPath, [script], options);

  assert.ok(explicit.length > 0);
  assert.deepStrictEqual(inferred, explicit);
});

test("build-known refuses to emit an empty index if private bundled packs were not downloaded", () => {
  const dir = mkdtempSync(join(tmpdir(), "couchsubs-known-empty-"));
  try {
    writeFileSync(join(dir, "README.md"), "Manual packs must be fetched from private R2.");
    assert.throws(() => execFileSync(process.execPath, [script, dir], {
      stdio: ["ignore", "pipe", "pipe"],
    }), "empty known-keys.bin would allow retranslation of manual pack entries");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("build-known refuses packs without subtitle keys", () => {
  const dir = mkdtempSync(join(tmpdir(), "couchsubs-known-empty-pack-"));
  try {
    writeFileSync(join(dir, "test.json.gz"), gzipSync(JSON.stringify({
      format: 2, id: "test", entries: {}, segments: {},
    })));
    assert.throws(() => execFileSync(process.execPath, [script, dir], {
      stdio: ["ignore", "pipe", "pipe"],
    }));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("build-known still emits actual manual keys", () => {
  const dir = mkdtempSync(join(tmpdir(), "couchsubs-known-valid-"));
  try {
    writeFileSync(join(dir, "test.json.gz"), gzipSync(JSON.stringify({
      format: 2, id: "test", entries: { "0000000000000001": "One" },
      segments: { "0000000000000002": "Two" },
    })));
    const binary = execFileSync(process.execPath, [script, dir], { stdio: ["ignore", "pipe", "pipe"] });
    assert.equal(binary.length, 16);
    assert.deepEqual([...new BigUint64Array(binary.buffer, binary.byteOffset, 2)], [1n, 2n]);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("build-known rejects invalid manual translations rather than suppressing automatic replacements", () => {
  for (const [label, entries, segments] of [
    ["numeric entry", { "0000000000000001": 42 }, {}],
    ["blank entry", { "0000000000000001": "  " }, {}],
    ["null segment", { "0000000000000001": "Valid" }, { "0000000000000002": null }],
    ["format-2 fragments without a full line", {}, { "0000000000000002": "Orphan fragment" }],
  ]) {
    const dir = mkdtempSync(join(tmpdir(), "couchsubs-known-bad-value-"));
    try {
      writeFileSync(join(dir, "manual.json.gz"), gzipSync(JSON.stringify({
        format: 2, id: "manual", entries, segments,
      })));
      assert.throws(() => execFileSync(process.execPath, [script, dir], {
        stdio: ["ignore", "pipe", "pipe"],
      }), undefined, label + " should not suppress automatic translations");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  }
});

test("build-known rejects non-64-bit manual keys rather than silently truncating them", () => {
  for (const invalid of ["10000000000000001", "1", "ghijklmnopqrstuv"]) {
    const dir = mkdtempSync(join(tmpdir(), "couchsubs-known-invalid-"));
    try {
      const pack = { format: 2, id: "test", title: "Test", entries: { [invalid]: "Example" }, segments: {} };
      writeFileSync(join(dir, "test.json.gz"), gzipSync(JSON.stringify(pack)));
      assert.throws(() => execFileSync(process.execPath, [script, dir], {
        stdio: ["ignore", "pipe", "pipe"], maxBuffer: 1024 * 1024,
      }), undefined, "invalid key should fail: " + invalid);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  }
});
