import test from "node:test";
import assert from "node:assert/strict";
import { ingestWebEvents, validateWebBatch } from "../src/web-events.ts";

const now = Date.now();
const sessionID = "96f5d323-18eb-4c27-9384-e19d0818649b";
const batch = () => ({
  schemaVersion: 1, sessionID, locale: "en-US", device: "desktop",
  events: [{ id: "c8447224-3334-4f3e-8876-6a4605a46101", name: "viewer_ready",
    occurredAt: new Date(now).toISOString(),
    properties: { model_id: "35559c2236d04c1a80ccbe08cae863c6", surface: "model", duration_ms: 1500 } }]
});
const request = (payload: unknown, origin = "https://ar-asia.luopeike.com") => new Request("https://littlenature-api.luopeike.com/v1/web-events", {
  method: "POST", headers: { origin, "content-type": "application/json" }, body: JSON.stringify(payload)
});
function environment(fail = false) {
  const rows: unknown[][] = [];
  const limit = { limit: async () => ({ success: true }) };
  return { rows, env: {
    DB: { prepare: () => ({ bind: (...values: unknown[]) => { rows.push(values); return {}; } }), batch: async () => { if (fail) throw new Error("database unavailable"); } },
    INSTALLATION_HASH_KEY: "test-only-secret", INSTALLATION_RATE_LIMITER: limit, GLOBAL_RATE_LIMITER: limit
  } };
}

test("valid website events preserve only bounded, fixed properties", () => {
  assert.equal(validateWebBatch(batch(), now)?.events[0].properties.duration_ms, 1500);
});

test("free-form search and page URLs cannot enter analytics", () => {
  for (const key of ["search", "query", "url", "referrer"]) {
    const value = batch();
    Object.assign(value.events[0].properties, { [key]: "private user text" });
    assert.equal(validateWebBatch(value, now), null);
  }
});

test("unknown locales, events, and invalid elapsed time are rejected", () => {
  const locale = batch(); locale.locale = "unknown"; assert.equal(validateWebBatch(locale, now), null);
  const event = batch(); event.events[0].name = "search_text"; assert.equal(validateWebBatch(event, now), null);
  const duration = batch(); duration.events[0].properties.duration_ms = 99999999; assert.equal(validateWebBatch(duration, now), null);
});

test("only the production website origin can post or preflight", async () => {
  const { env, rows } = environment();
  const denied = await ingestWebEvents(request(batch(), "https://other.example"), env as never);
  assert.equal(denied.status, 403); assert.equal(rows.length, 0);
  assert.equal(denied.headers.get("access-control-allow-origin"), null);
  const allowed = await ingestWebEvents(new Request("https://littlenature-api.luopeike.com/v1/web-events", {
    method: "OPTIONS", headers: { origin: "https://ar-asia.luopeike.com" }
  }), env as never);
  assert.equal(allowed.status, 204);
  assert.equal(allowed.headers.get("access-control-allow-origin"), "https://ar-asia.luopeike.com");
});

test("stored sessions are hashed and isolated from raw identifiers", async () => {
  const { env, rows } = environment();
  const result = await ingestWebEvents(request(batch()), env as never);
  assert.equal(result.status, 202);
  assert.match(rows[0][1] as string, /^[a-f0-9]{64}$/);
  assert.equal(JSON.stringify(rows).includes(sessionID), false);
});

test("database failure is a controlled response with correct CORS", async () => {
  const { env } = environment(true);
  const result = await ingestWebEvents(request(batch()), env as never);
  assert.equal(result.status, 503);
  assert.equal(result.headers.get("access-control-allow-origin"), "https://ar-asia.luopeike.com");
});
