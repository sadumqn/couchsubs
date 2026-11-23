// SPDX-License-Identifier: AGPL-3.0-only
import assert from "node:assert/strict";
import test from "node:test";
import { CLAUDE_BATCHES_URL, collectBatches } from "../src/autopack.js";

const KEY = "1111111111111111";
const makeCache = () => ({
  lines: {}, skip: {}, fail: {},
  batches: [{
    id: "msgbatch_final",
    at: Date.parse("2026-11-21T03:00:00Z"),
    reqs: { c0: [{ pool: KEY, k: KEY, en: "Keep moving now." }] },
  }],
});

test("an ended batch with zero successes and no results URL no longer holds the pending queue", async (t) => {
  const cache = makeCache();
  let requests = 0;
  t.mock.method(globalThis, "fetch", async (url) => {
    requests++;
    assert.equal(url, CLAUDE_BATCHES_URL + "/msgbatch_final");
    return new Response(JSON.stringify({
      processing_status: "ended", results_url: null,
      request_counts: { processing: 0, succeeded: 0, errored: 1, canceled: 0, expired: 0 },
    }));
  });
  const result = await collectBatches({ ANTHROPIC_API_KEY: "sk-test" }, cache);
  assert.equal(requests, 1);
  assert.equal(result.lines, 0);
  assert.deepEqual(cache.batches, [], "terminal all-failed batch must free a pending batch slot");
  assert.equal(cache.fail[KEY], 1, "untranslated lines remain eligible for retry");
});

test("an ended all-canceled batch with a blank results URL also frees the slot", async (t) => {
  const cache = makeCache();
  t.mock.method(globalThis, "fetch", async (url) => {
    assert.equal(url, CLAUDE_BATCHES_URL + "/msgbatch_final");
    return new Response(JSON.stringify({
      processing_status: "ended", results_url: "",
      request_counts: { processing: 0, succeeded: 0, errored: 0, canceled: 1, expired: 0 },
    }));
  });
  await collectBatches({ ANTHROPIC_API_KEY: "sk-test" }, cache);
  assert.deepEqual(cache.batches, []);
  assert.equal(cache.fail[KEY], 1);
});

test("an ended batch with a claimed success but missing results URL retains retry state", async (t) => {
  const cache = makeCache();
  t.mock.method(globalThis, "fetch", async () => new Response(JSON.stringify({
    processing_status: "ended", results_url: null,
    request_counts: { processing: 0, succeeded: 1, errored: 0, canceled: 0, expired: 0 },
  })));
  await collectBatches({ ANTHROPIC_API_KEY: "sk-test" }, cache);
  assert.equal(cache.batches.length, 1, "never discard potentially billable successes");
  assert.equal(cache.fail[KEY], undefined);
});

test("a processing batch without results URL remains pending", async (t) => {
  const cache = makeCache();
  t.mock.method(globalThis, "fetch", async () => new Response(JSON.stringify({
    processing_status: "in_progress", results_url: null,
    request_counts: { processing: 1, succeeded: 0, errored: 0, canceled: 0, expired: 0 },
  })));
  await collectBatches({ ANTHROPIC_API_KEY: "sk-test" }, cache);
  assert.equal(cache.batches.length, 1);
  assert.equal(cache.fail[KEY], undefined);
});
