// SPDX-License-Identifier: AGPL-3.0-only
// CouchSubs game packs (Cloudflare Worker + R2). Paketler ücretsizdir: telefon uygulaması yeni ve güncellenen paketleri
// buradan indirir (uygulamayla gelenlerin üstüne). Hesap ya da giriş yoktur.
// GET /v1/packs     : paket listesi ve sürümleri (R2'deki index.json).
// GET /v1/packs/:id : paket dosyası (.json.gz), x-pack-sha256 başlığıyla.
// Kötüye kullanıma karşı IP başına basit sınır: saatte RATE_LIMIT indirme (Worker örneği başına, bellekte).
// Paketler yalnız uygulama içinden alınsın diye her istek imzalıdır: x-couchsubs-time (unix saniye) ve
// x-couchsubs-signature = hex(HMAC-SHA256(APP_SECRET, "GET\n<yol>\n<zaman>")). Zaman ±5 dakika içinde olmalı. Geçişte
// (UNSIGNED_UNTIL'e kadar) imzasız istek kabul edilip loglanır, sonra 403; yanlış ya da süresi geçmiş imza hep 403.
// CORS başlığı gönderilmez: tarayıcıdaki başka bir site paketleri okuyamaz.

export interface R2ObjectLike {
  body: ReadableStream | null;
  size: number;
  httpEtag: string;
  customMetadata?: Record<string, string>;
  text(): Promise<string>;
}

export interface R2BucketLike {
  get(key: string, options?: { onlyIf?: { etagDoesNotMatch?: string } }): Promise<R2ObjectLike | null>;
}

export interface Env {
  PACKS: R2BucketLike;
  /** Uygulamalara derlemede gömülen paylaşılan sır (`wrangler secret put APP_SECRET`). */
  APP_SECRET?: string;
}

export interface PackInfo {
  id: string;
  title: string;
  version: number;
  sha256: string;
  size: number;
  entries: number;
}

const PACK_ID = /^[a-z0-9][a-z0-9-]{0,63}$/;
const SHA256_HEX = /^[a-f0-9]{64}$/i;

/** Bozuk indeks girdileri istemcilerin kurulu paket kayıtlarını kaybetmesine neden olabilir. */
function validPack(value: unknown): value is PackInfo {
  if (!value || typeof value !== "object") return false;
  const pack = value as Record<string, unknown>;
  return typeof pack.id === "string" && PACK_ID.test(pack.id)
    && typeof pack.title === "string" && pack.title.trim().length > 0
    && Number.isSafeInteger(pack.version) && (pack.version as number) >= 0
    && typeof pack.sha256 === "string" && SHA256_HEX.test(pack.sha256)
    && Number.isSafeInteger(pack.size) && (pack.size as number) > 0
    && Number.isSafeInteger(pack.entries) && (pack.entries as number) > 0;
}

/** Bir IP'nin bir saatte indirebileceği paket dosyası. */
export const RATE_LIMIT = 30;
/** İmzasız istekler bu ana kadar kabul edilir (eski uygulama sürümleri güncellensin diye), sonra 403. */
export const UNSIGNED_UNTIL = Date.parse("2026-11-29T23:59:00Z");
/** İmzadaki zamanın sunucu saatinden en çok sapması. */
export const SIGNATURE_SKEW_MS = 5 * 60 * 1000;
const WINDOW_MS = 60 * 60 * 1000;

const json = (body: unknown, status = 200, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json; charset=utf-8", ...extra } });

/** IP → bu penceredeki indirme sayısı. Örnek yeniden başlayınca sıfırlanır; amaç kaba kötüye kullanımı kesmek. */
export class RateLimiter {
  private readonly hits = new Map<string, { count: number; since: number }>();

  constructor(private readonly limit = RATE_LIMIT, private readonly windowMs = WINDOW_MS) {}

  /** İzin verilirse null, yoksa kaç saniye sonra yeniden denenebileceği. */
  take(ip: string, now: number): number | null {
    let entry = this.hits.get(ip);
    if (!entry || now - entry.since >= this.windowMs) {
      entry = { count: 0, since: now };
      this.hits.set(ip, entry);
    }
    if (entry.count >= this.limit) return Math.ceil((entry.since + this.windowMs - now) / 1000);
    entry.count++;
    // Bellek büyümesin: çok IP birikirse süresi geçenler atılır.
    if (this.hits.size > 10_000) for (const [key, value] of this.hits) if (now - value.since >= this.windowMs) this.hits.delete(key);
    return null;
  }
}

const limiter = new RateLimiter();

const encoder = new TextEncoder();
const keys = new Map<string, Promise<CryptoKey>>();

function hmacKey(secret: string): Promise<CryptoKey> {
  let key = keys.get(secret);
  if (!key) {
    key = crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
    keys.set(secret, key);
  }
  return key;
}

/** hex(HMAC-SHA256(secret, method + "\n" + path + "\n" + time)); istemcilerdeki imzayla aynı. */
export async function sign(secret: string, method: string, path: string, time: string): Promise<string> {
  const mac = await crypto.subtle.sign("HMAC", await hmacKey(secret), encoder.encode(`${method}\n${path}\n${time}`));
  return [...new Uint8Array(mac)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function sameText(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** null: istek geçer; yoksa 403 yanıtı. */
async function authorize(request: Request, url: URL, env: Env, now: number): Promise<Response | null> {
  const time = request.headers.get("x-couchsubs-time");
  const signature = request.headers.get("x-couchsubs-signature");
  if (!time && !signature) {
    if (now <= UNSIGNED_UNTIL) {
      console.log(JSON.stringify({ unsigned: url.pathname }));
      return null;
    }
    return json({ error: "forbidden" }, 403, { "cache-control": "no-store" });
  }
  // Sır tanımlı değilse imza doğrulanamaz: geçişte geçer, sonra kapalı.
  if (!env.APP_SECRET) {
    console.log(JSON.stringify({ unverified: url.pathname, reason: "no_secret" }));
    return now <= UNSIGNED_UNTIL ? null : json({ error: "forbidden" }, 403, { "cache-control": "no-store" });
  }
  const seconds = /^[0-9]{1,12}$/.test(time ?? "") ? Number(time) : NaN;
  const fresh = Number.isFinite(seconds) && Math.abs(seconds * 1000 - now) <= SIGNATURE_SKEW_MS;
  const expected = fresh ? await sign(env.APP_SECRET, request.method, url.pathname, time!) : "";
  if (fresh && signature && sameText(signature.toLowerCase(), expected)) return null;
  return json({ error: "forbidden" }, 403, { "cache-control": "no-store" });
}

async function readIndex(env: Env): Promise<PackInfo[] | null> {
  try {
    const object = await env.PACKS.get("index.json");
    if (!object) return null;
    const parsed = JSON.parse(await object.text()) as { packs?: unknown };
    if (!Array.isArray(parsed?.packs) || !parsed.packs.every(validPack)) return null;
    // Aynı kimliğin birden çok sürümü, istemcinin hangi paketi indireceğini belirsizleştirir.
    if (new Set(parsed.packs.map((pack: PackInfo) => pack.id)).size !== parsed.packs.length) return null;
    return parsed.packs;
  } catch {
    return null;
  }
}

async function list(env: Env): Promise<Response> {
  const packs = await readIndex(env);
  // Eksik/bozuk index başarıyla boş liste gibi gönderilirse istemciler kurulu paketleri silebilir.
  if (packs === null) return json({ error: "index_unavailable" }, 503, { "cache-control": "no-store" });
  return json({ packs }, 200, { "cache-control": "public, max-age=300" });
}

async function download(request: Request, env: Env, id: string, rate: RateLimiter, now: number): Promise<Response> {
  if (!PACK_ID.test(id)) return json({ error: "not_found" }, 404);
  const object = await env.PACKS.get(`packs/${id}.json.gz`);
  if (!object || !object.body) return json({ error: "not_found" }, 404);
  const headers: Record<string, string> = {
    "content-type": "application/gzip",
    "content-length": String(object.size),
    etag: object.httpEtag,
    // Havuzdan otomatik paketler her gece değişebilir: önbellek her seferinde ETag ile sorar (değişmediyse 304), eski
    // dosya listedeki yeni SHA-256'ya takılmaz.
    "cache-control": "public, no-cache",
  };
  const sha = object.customMetadata?.sha256;
  if (sha) headers["x-pack-sha256"] = sha;
  // If-None-Match zayıf ETag, virgülle ayrılmış liste veya mevcut kaynak için * içerebilir.
  const condition = request.headers.get("if-none-match");
  // If-None-Match uses weak ETag comparison: either side may carry W/.
  const currentTag = object.httpEtag.replace(/^W\//, "");
  const matches = condition?.split(",").some((value) => {
    const tag = value.trim();
    return tag === "*" || tag.replace(/^W\//, "") === currentTag;
  });
  if (matches) return new Response(null, { status: 304, headers });
  // Only a 200 response transfers a pack. Cache validation and missing IDs do not use download quota.
  const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
  const retry = rate.take(ip, now);
  if (retry !== null) return json({ error: "rate_limited" }, 429, { "retry-after": String(retry) });
  return new Response(object.body, { status: 200, headers });
}

export async function handle(request: Request, env: Env, rate: RateLimiter = limiter, now: number = Date.now()): Promise<Response> {
  const url = new URL(request.url);
  if (request.method !== "GET") return json({ error: "method_not_allowed" }, 405);
  const denied = await authorize(request, url, env, now);
  if (denied) return denied;
  if (url.pathname === "/v1/packs") return list(env);
  const match = /^\/v1\/packs\/([^/]+)$/.exec(url.pathname);
  if (match) {
    let id: string;
    try { id = decodeURIComponent(match[1]); }
    catch { return json({ error: "not_found" }, 404); }
    return download(request, env, id, rate, now);
  }
  return json({ error: "not_found" }, 404);
}

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handle(request, env).catch(() => json({ error: "internal" }, 500));
  },
};
