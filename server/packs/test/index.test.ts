// SPDX-License-Identifier: AGPL-3.0-only
import { describe, expect, it } from "vitest";
import { handle, RateLimiter, RATE_LIMIT, sign, UNSIGNED_UNTIL, type Env, type R2BucketLike } from "../src/index";

const SECRET = "test-secret-not-real";
/** Geçiş bittikten sonraki bir an: imzasız istekler artık reddedilir. */
const AFTER = UNSIGNED_UNTIL + 24 * 3600 * 1000;

const index = { packs: [{ id: "gta-v", title: "GTA V", version: 3, sha256: "ab".repeat(32), size: 5, entries: 2 }] };

function bucket(): R2BucketLike {
  const files: Record<string, { data: Uint8Array; meta?: Record<string, string> }> = {
    "index.json": { data: new TextEncoder().encode(JSON.stringify(index)) },
    "packs/gta-v.json.gz": { data: new Uint8Array([0x1f, 0x8b, 1, 2, 3]), meta: { sha256: "ab".repeat(32) } },
  };
  return {
    async get(key) {
      const file = files[key];
      if (!file) return null;
      return {
        body: new Blob([file.data]).stream(),
        size: file.data.length,
        httpEtag: '"etag-1"',
        customMetadata: file.meta,
        text: async () => new TextDecoder().decode(file.data),
      };
    },
  };
}

function indexBucket(raw: string | null): R2BucketLike {
  return {
    async get(key) {
      if (key !== "index.json" || raw === null) return null;
      return { body: null, size: raw.length, httpEtag: '"index"', text: async () => raw };
    },
  };
}

const env = (): Env => ({ PACKS: bucket(), APP_SECRET: SECRET });
const get = (path: string, headers: Record<string, string> = {}) =>
  new Request(`https://packs.example${path}`, { headers: { "cf-connecting-ip": "203.0.113.7", ...headers } });

/** İsteği verilen ana göre imzalayıp işler (uygulamaların gönderdiği gibi). */
async function call(request: Request, environment: Env, rate: RateLimiter = new RateLimiter(), now = AFTER): Promise<Response> {
  const url = new URL(request.url);
  const time = String(Math.floor(now / 1000));
  const headers = new Headers(request.headers);
  headers.set("x-couchsubs-time", time);
  headers.set("x-couchsubs-signature", await sign(SECRET, request.method, url.pathname, time));
  return handle(new Request(request.url, { method: request.method, headers }), { APP_SECRET: SECRET, ...environment }, rate, now);
}

describe("GET /v1/packs", () => {
  it.each([null, "{}", '{"packs":null}', '{"packs":'])
    ("reports index unavailability rather than an empty pack list (%s)", async (raw) => {
      const response = await call(get("/v1/packs"), { PACKS: indexBucket(raw) }, new RateLimiter());
      expect(response.status).toBe(503);
      expect(response.headers.get("cache-control")).toBe("no-store");
    });

  it.each([
    ["invalid checksum", { sha256: "bad" }],
    ["unsafe pack id", { id: "../outside" }],
    ["missing title", { title: null }],
    ["invalid version", { version: "new" }],
    ["invalid size", { size: -1 }],
    ["invalid entry count", { entries: -1 }],
    ["zero translations", { entries: 0 }],
    ["empty archive size", { size: 0 }],
  ])("rejects invalid pack metadata (%s)", async (_label, changes) => {
    const entry = { ...index.packs[0], ...changes };
    const response = await call(get("/v1/packs"), { PACKS: indexBucket(JSON.stringify({ packs: [entry] })) }, new RateLimiter());
    expect(response.status).toBe(503);
    expect(response.headers.get("cache-control")).toBe("no-store");
  });

  it("accepts valid automatically generated pack metadata", async () => {
    const auto = { ...index.packs[0], id: "pool-gta-v", auto: true, titleId: "PPSA01234" };
    const response = await call(get("/v1/packs"), { PACKS: indexBucket(JSON.stringify({ packs: [auto] })) }, new RateLimiter());
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ packs: [auto] });
  });

  it("keeps a valid empty list as a successful response", async () => {
    const response = await call(get("/v1/packs"), { PACKS: indexBucket('{"packs":[]}') }, new RateLimiter());
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ packs: [] });
  });

  it("lists packs", async () => {
    const response = await call(get("/v1/packs"), env(), new RateLimiter());
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("public, max-age=300");
    expect(await response.json()).toEqual(index);
  });
});

describe("GET /v1/packs/:id", () => {
  it("streams the pack without sign-in", async () => {
    const response = await call(get("/v1/packs/gta-v"), env(), new RateLimiter());
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("application/gzip");
    expect(response.headers.get("x-pack-sha256")).toBe("ab".repeat(32));
    expect(response.headers.get("cache-control")).toBe("public, no-cache");
    expect(response.headers.get("etag")).toBe('"etag-1"');
    expect(new Uint8Array(await response.arrayBuffer())).toEqual(new Uint8Array([0x1f, 0x8b, 1, 2, 3]));
  });

  it("answers 304 when the cached copy is current", async () => {
    const response = await call(get("/v1/packs/gta-v", { "if-none-match": '"etag-1"' }), env(), new RateLimiter());
    expect(response.status).toBe(304);
  });

  it.each(['W/"etag-1"', '"etag-1"'])(
    "accepts an existing weak R2 ETag with If-None-Match %s without charging download quota",
    async (condition) => {
      const original = bucket();
      const weak: R2BucketLike = {
        async get(key) {
          const item = await original.get(key);
          if (!item || key !== "packs/gta-v.json.gz") return item;
          return { ...item, httpEtag: 'W/"etag-1"' };
        },
      };
      const rate = new RateLimiter(1);
      const reply = await call(
        get("/v1/packs/gta-v", { "if-none-match": condition }),
        { PACKS: weak }, rate);
      expect(reply.status).toBe(304);
      expect(reply.headers.get("etag")).toBe('W/"etag-1"');
      // A conditional hit should not consume the sole 200-download allowance.
      const download = await call(get("/v1/packs/gta-v"), { PACKS: weak }, rate);
      expect(download.status).toBe(200);
    },
  );

  it("rejects unknown packs and odd ids", async () => {
    expect((await call(get("/v1/packs/yok"), env(), new RateLimiter())).status).toBe(404);
    expect((await call(get("/v1/packs/..%2Findex.json"), env(), new RateLimiter())).status).toBe(404);
    expect((await call(get("/v1/other"), env(), new RateLimiter())).status).toBe(404);
  });

  it("only allows GET", async () => {
    const response = await call(new Request("https://packs.example/v1/packs", { method: "POST" }), env(), new RateLimiter());
    expect(response.status).toBe(405);
  });

  it("limits downloads per IP", async () => {
    const rate = new RateLimiter(2, 60_000);
    const now = 1_000_000;
    expect((await call(get("/v1/packs/gta-v"), env(), rate, now)).status).toBe(200);
    expect((await call(get("/v1/packs/gta-v"), env(), rate, now)).status).toBe(200);
    const limited = await call(get("/v1/packs/gta-v"), env(), rate, now + 1000);
    expect(limited.status).toBe(429);
    expect(limited.headers.get("retry-after")).toBe("59");
    // Başka IP etkilenmez; pencere dolunca yeniden açılır.
    expect((await call(get("/v1/packs/gta-v", { "cf-connecting-ip": "198.51.100.1" }), env(), rate, now)).status).toBe(200);
    expect((await call(get("/v1/packs/gta-v"), env(), rate, now + 60_000)).status).toBe(200);
    // Liste sınıra sayılmaz.
    expect((await call(get("/v1/packs"), env(), rate, now + 60_001)).status).toBe(200);
  });
});

it("only charges successful pack downloads against the hourly limit", async () => {
  const rate = new RateLimiter(1, 60_000);
  const now = 1_000_000;
  expect((await call(get("/v1/packs/missing"), env(), rate, now)).status).toBe(404);
  expect((await call(get("/v1/packs/gta-v", { "if-none-match": '"etag-1"' }), env(), rate, now)).status).toBe(304);
  expect((await call(get("/v1/packs/gta-v"), env(), rate, now)).status).toBe(200);
  expect((await call(get("/v1/packs/gta-v", { "if-none-match": '"etag-1"' }), env(), rate, now)).status).toBe(304);
  expect((await call(get("/v1/packs/gta-v"), env(), rate, now)).status).toBe(429);
});

describe("RateLimiter", () => {
  it("defaults to 30 downloads an hour", () => {
    expect(RATE_LIMIT).toBe(30);
    const rate = new RateLimiter();
    for (let i = 0; i < RATE_LIMIT; i++) expect(rate.take("ip", 0)).toBeNull();
    expect(rate.take("ip", 0)).toBe(3600);
  });
});

it("rejects a pack index containing duplicate IDs instead of exposing ambiguous versions", async () => {
  const first = index.packs[0];
  const second = { ...first, title: "Wrong game", version: 4, sha256: "cd".repeat(32) };
  const response = await call(
    get("/v1/packs"),
    { PACKS: indexBucket(JSON.stringify({ packs: [first, second] })) },
    new RateLimiter(),
  );
  expect(response.status).toBe(503);
  expect(response.headers.get("cache-control")).toBe("no-store");
});

it.each([
  ["weak ETag", 'W/"etag-1"'],
  ["ETag list", '"old-copy", W/"etag-1"'],
  ["wildcard", "*"],
])("returns 304 for a matching If-None-Match %s", async (_kind, condition) => {
  const response = await call(
    get("/v1/packs/gta-v", { "if-none-match": condition }),
    env(),
    new RateLimiter(),
  );
  expect(response.status).toBe(304);
  expect(response.headers.get("etag")).toBe('"etag-1"');
});

it("still sends the pack when If-None-Match is unrelated", async () => {
  const response = await call(
    get("/v1/packs/gta-v", { "if-none-match": '"old-copy", W/"other"' }),
    env(),
    new RateLimiter(),
  );
  expect(response.status).toBe(200);
});

it("returns 404 rather than crashing on invalid percent-encoded pack IDs", async () => {
  const response = await call(
    get("/v1/packs/%E0%A4%A"),
    env(),
    new RateLimiter(),
  );
  expect(response.status).toBe(404);
});

describe("signed requests", () => {
  const unsigned = (now: number) => handle(get("/v1/packs/gta-v"), env(), new RateLimiter(), now);
  const signedAt = async (time: number, now: number, secret = SECRET, path = "/v1/packs/gta-v") => {
    const t = String(Math.floor(time / 1000));
    const request = get("/v1/packs/gta-v", { "x-couchsubs-time": t, "x-couchsubs-signature": await sign(secret, "GET", path, t) });
    return handle(request, env(), new RateLimiter(), now);
  };

  it("accepts unsigned requests until the transition ends, then refuses them", async () => {
    expect((await unsigned(UNSIGNED_UNTIL - 1000)).status).toBe(200);
    expect((await handle(get("/v1/packs"), env(), new RateLimiter(), UNSIGNED_UNTIL)).status).toBe(200);
    const refused = await unsigned(UNSIGNED_UNTIL + 1000);
    expect(refused.status).toBe(403);
    expect((await handle(get("/v1/packs"), env(), new RateLimiter(), AFTER)).status).toBe(403);
  });

  it("accepts a valid signature within five minutes", async () => {
    expect((await signedAt(AFTER, AFTER)).status).toBe(200);
    expect((await signedAt(AFTER - 4 * 60_000, AFTER)).status).toBe(200);
    expect((await signedAt(AFTER + 4 * 60_000, AFTER)).status).toBe(200);
  });

  it("refuses stale, future, wrong-secret and wrong-path signatures, even during the transition", async () => {
    const during = UNSIGNED_UNTIL - 3600_000;
    expect((await signedAt(during - 6 * 60_000, during)).status).toBe(403);
    expect((await signedAt(during + 6 * 60_000, during)).status).toBe(403);
    expect((await signedAt(during, during, "other-secret")).status).toBe(403);
    expect((await signedAt(during, during, SECRET, "/v1/packs")).status).toBe(403);
    const garbage = get("/v1/packs/gta-v", { "x-couchsubs-time": "abc", "x-couchsubs-signature": "00" });
    expect((await handle(garbage, env(), new RateLimiter(), during)).status).toBe(403);
  });

  it("sends no CORS headers", async () => {
    const response = await call(get("/v1/packs", { origin: "https://example.com" }), env());
    expect(response.status).toBe(200);
    expect(response.headers.get("access-control-allow-origin")).toBeNull();
  });
});
