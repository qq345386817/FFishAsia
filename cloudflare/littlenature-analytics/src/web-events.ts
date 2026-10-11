interface WebEnv {
  DB: D1Database;
  INSTALLATION_HASH_KEY: string;
  INSTALLATION_RATE_LIMITER: RateLimit;
  GLOBAL_RATE_LIMITER: RateLimit;
}

interface WebEvent {
  id: string;
  name: string;
  occurredAt: string;
  properties: Record<string, string | number>;
}

interface WebBatch {
  schemaVersion: 1;
  sessionID: string;
  locale: string;
  device: string;
  events: WebEvent[];
}

const ORIGIN = "https://ar-asia.luopeike.com";
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
const MODEL = /^[a-f0-9]{32}$/i;
const LOCALES = new Set(["en-US", "de-DE", "ja", "ko", "zh-Hans", "zh-Hant"]);
const DEVICES = new Set(["mobile", "tablet", "desktop"]);
const SURFACES = new Set(["home", "catalog", "model", "theme", "study"]);
const THEMES = new Set(["motion", "small-creatures", "pond-life", "flowers"]);
const MODEL_EVENTS = new Set(["model_open", "viewer_start", "viewer_ready", "viewer_error", "model_interaction", "animation_play", "animation_pause"]);
const NAMES = new Set([...MODEL_EVENTS, "catalog_view", "theme_view", "cards_print", "store_click"]);
const KEYS = new Set(["model_id", "theme", "surface", "duration_ms", "card_count", "layout"]);

function record(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function validateWebBatch(payload: unknown, now: number): WebBatch | null {
  if (!record(payload) || payload.schemaVersion !== 1) return null;
  if (typeof payload.sessionID !== "string" || !UUID.test(payload.sessionID)) return null;
  if (typeof payload.locale !== "string" || !LOCALES.has(payload.locale)) return null;
  if (typeof payload.device !== "string" || !DEVICES.has(payload.device)) return null;
  if (!Array.isArray(payload.events) || !payload.events.length || payload.events.length > 20) return null;
  const events: WebEvent[] = [];
  for (const value of payload.events) {
    if (!record(value) || typeof value.id !== "string" || !UUID.test(value.id)) return null;
    if (typeof value.name !== "string" || !NAMES.has(value.name)) return null;
    if (typeof value.occurredAt !== "string") return null;
    const time = Date.parse(value.occurredAt);
    if (!Number.isFinite(time) || time < now - 86400000 || time > now + 300000) return null;
    if (!record(value.properties)) return null;
    const properties: Record<string, string | number> = {};
    for (const [key, item] of Object.entries(value.properties)) {
      if (!KEYS.has(key)) return null;
      if (key === "model_id" && (typeof item !== "string" || !MODEL.test(item))) return null;
      if (key === "theme" && (typeof item !== "string" || !THEMES.has(item))) return null;
      if (key === "surface" && (typeof item !== "string" || !SURFACES.has(item))) return null;
      if (key === "layout" && item !== "named" && item !== "matching") return null;
      if (key === "duration_ms" && (typeof item !== "number" || !Number.isInteger(item) || item < 0 || item > 120000 || item % 250 !== 0)) return null;
      if (key === "card_count" && (typeof item !== "number" || !Number.isInteger(item) || item < 1 || item > 200)) return null;
      properties[key] = item as string | number;
    }
    if (!properties.surface) return null;
    if (MODEL_EVENTS.has(value.name) && (!properties.model_id || properties.surface !== "model")) return null;
    if (value.name === "theme_view" && (!properties.theme || properties.surface !== "theme")) return null;
    if (value.name === "cards_print" && (!properties.card_count || !properties.layout || properties.surface !== "study")) return null;
    events.push({ id: value.id.toLowerCase(), name: value.name, occurredAt: value.occurredAt, properties });
  }
  return { schemaVersion: 1, sessionID: payload.sessionID.toLowerCase(), locale: payload.locale, device: payload.device, events };
}

function response(body: unknown, status: number, cors = true): Response {
  const headers = new Headers({
    "content-type": "application/json; charset=utf-8", "cache-control": "no-store",
    "x-content-type-options": "nosniff", "vary": "Origin",
  });
  if (cors) {
    headers.set("access-control-allow-origin", ORIGIN);
    headers.set("access-control-allow-methods", "POST, OPTIONS");
    headers.set("access-control-allow-headers", "Content-Type");
    headers.set("access-control-max-age", "600");
  }
  return new Response(status === 204 ? null : JSON.stringify(body), { status, headers });
}

async function hashSession(value: string, secret: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const digest = await crypto.subtle.sign("HMAC", key, encoder.encode("web:" + value));
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, "0")).join("");
}

export async function ingestWebEvents(request: Request, env: WebEnv): Promise<Response> {
  if (request.headers.get("origin") !== ORIGIN) return response({ error: "origin_not_allowed" }, 403, false);
  if (request.method === "OPTIONS") return response(null, 204);
  if (request.method !== "POST") return response({ error: "method_not_allowed" }, 405);
  if (!(request.headers.get("content-type") || "").toLowerCase().startsWith("application/json")) return response({ error: "unsupported_media_type" }, 415);
  if (Number(request.headers.get("content-length") || 0) > 16384) return response({ error: "payload_too_large" }, 413);
  if (!(await env.GLOBAL_RATE_LIMITER.limit({ key: "web-events" })).success) return response({ error: "rate_limited" }, 429);
  const body = await request.text();
  if (new TextEncoder().encode(body).length > 16384) return response({ error: "payload_too_large" }, 413);
  let payload: unknown;
  try { payload = JSON.parse(body); }
  catch { return response({ error: "invalid_json" }, 400); }
  const batch = validateWebBatch(payload, Date.now());
  if (!batch) return response({ error: "invalid_payload" }, 400);
  if (!(await env.INSTALLATION_RATE_LIMITER.limit({ key: "web:" + batch.sessionID })).success) return response({ error: "rate_limited" }, 429);
  try {
    const sessionHash = await hashSession(batch.sessionID, env.INSTALLATION_HASH_KEY);
    const statement = env.DB.prepare(
      "INSERT OR IGNORE INTO web_events (event_id, session_id_hash, event_name, occurred_at, locale, device_class, properties_json) VALUES (?, ?, ?, ?, ?, ?, ?)"
    );
    await env.DB.batch(batch.events.map(event => statement.bind(
      event.id, sessionHash, event.name, Date.parse(event.occurredAt),
      batch.locale, batch.device, JSON.stringify(event.properties)
    )));
    return response({ accepted: batch.events.length }, 202);
  } catch {
    return response({ error: "temporarily_unavailable" }, 503);
  }
}
