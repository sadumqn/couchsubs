// SPDX-License-Identifier: AGPL-3.0-only
// Paket klasöründen (varsayılan: core/Sources/CouchSubsCore/Resources/packs) R2'ye yüklenecek index.json'u üretir.
// Kullanım: node scripts/build-index.mjs [paket-klasörü] [sürüm] > index.json
import { createHash } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { gunzipSync } from "node:zlib";

const dir = process.argv[2] ?? fileURLToPath(new URL("../../../core/Sources/CouchSubsCore/Resources/packs", import.meta.url));
const version = Number(process.argv[3] ?? Math.floor(Date.now() / 1000));
if (!Number.isSafeInteger(version) || version < 0) {
  throw new Error("Pack index version must be a nonnegative safe integer");
}

const packs = readdirSync(dir)
  .filter((name) => name.endsWith(".json.gz"))
  .sort()
  .map((name) => {
    const data = readFileSync(join(dir, name));
    const parsed = JSON.parse(gunzipSync(data).toString("utf8"));
    const fileId = name.replace(/\.json\.gz$/, "");
    const id = parsed.id ?? fileId;
    // README'deki R2 yükleme döngüsü dosya adını kullanır, API ise indeks kimliğini.
    if (id !== fileId) throw new Error(`Pack ID ${id} does not match file ${name}`);
    // Keep the generated index compatible with the packs Worker validator.
    if (typeof id !== "string" || !/^[a-z0-9][a-z0-9-]{0,63}$/.test(id)) {
      throw new Error("Invalid pack ID");
    }
    const title = parsed.title ?? id;
    if (typeof title !== "string" || !title.trim()) throw new Error("Invalid pack title");
    const record = (v) => v && typeof v === "object" && !Array.isArray(v);
    if (parsed.format === 2 && !record(parsed.entries)) throw new Error("Invalid format 2 pack entries");
    const source = parsed.entries ?? parsed;
    if (!record(source)) throw new Error("Invalid pack entries");
    const entries = Object.keys(source).length;
    return { id, title, version, sha256: createHash("sha256").update(data).digest("hex"), size: data.length, entries };
  });

// Pack archives live in private R2 and are not checked into this repository.
// An empty local folder must not produce a publishable index: clients treat
// { packs: [] } as a request to remove all their downloaded game packs.
if (packs.length === 0) throw new Error("No game pack archives found; fetch the private packs before building index.json");

process.stdout.write(JSON.stringify({ packs }, null, 2) + "\n");
