interface Env {
  DB: D1Database;
  INSTALLATION_HASH_KEY: string;
  INSTALLATION_RATE_LIMITER: RateLimit;
  GLOBAL_RATE_LIMITER: RateLimit;
}

interface AnalyticsBatch {
  schemaVersion: number;
  appID: string;
  installationID: string;
  sessionID: string;
  context: {
    appVersion: string;
    buildNumber: string;
    platform: string;
    osVersion: string;
    locale: string;
  };
  events: AnalyticsEvent[];
}

interface AnalyticsEvent {
  id: string;
  name: string;
  occurredAt: string;
  properties?: Record<string, string>;
}

const APP_ID = "little-nature";
const MAX_REQUEST_BYTES = 64 * 1024;
const MAX_EVENTS_PER_BATCH = 50;
const MAX_EVENT_AGE_MS = 31 * 24 * 60 * 60 * 1000;
const MAX_FUTURE_SKEW_MS = 5 * 60 * 1000;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MODEL_ID_PATTERN = /^[0-9a-f]{32}$/i;
const EVENT_NAMES = new Set([
  "first_open",
  "app_open",
  "onboarding_complete",
  "catalog_view",
  "model_detail_open",
  "model_download_start",
  "model_download_complete",
  "preview_start",
  "ar_start",
  "review_prompt_requested"
]);
const PROPERTY_KEYS = new Set(["model_id", "category", "animated", "bundled"]);
const CATEGORIES = new Set(["animal", "plant", "special"]);
const BOOLEANS = new Set(["0", "1"]);
const PLATFORMS = new Set(["ios", "macos"]);

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/health") return healthResponse(env);
    if (request.method === "POST" && url.pathname === "/v1/events") return ingestEvents(request, env);
    return jsonResponse({ error: "not_found" }, 404);
  }
} satisfies ExportedHandler<Env>;

async function healthResponse(env: Env): Promise<Response> {
  try {
    await env.DB.prepare("SELECT 1").first();
    return jsonResponse({ status: "ok", service: "little-nature-analytics", schemaVersion: 1 });
  } catch {
    return jsonResponse({ status: "degraded" }, 503);
  }
}

async function ingestEvents(request: Request, env: Env): Promise<Response> {
  if (!(request.headers.get("content-type") ?? "").toLowerCase().startsWith("application/json")) {
    return jsonResponse({ error: "unsupported_media_type" }, 415);
  }
  if (Number(request.headers.get("content-length") ?? 0) > MAX_REQUEST_BYTES) {
    return jsonResponse({ error: "payload_too_large" }, 413);
  }
  const globalLimit = await env.GLOBAL_RATE_LIMITER.limit({ key: "events" });
  if (!globalLimit.success) return jsonResponse({ error: "rate_limited" }, 429);

  const rawBody = await request.text();
  if (new TextEncoder().encode(rawBody).byteLength > MAX_REQUEST_BYTES) {
    return jsonResponse({ error: "payload_too_large" }, 413);
  }
  let payload: unknown;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const validation = validateBatch(payload, Date.now());
  if (!validation.ok) return jsonResponse({ error: "invalid_payload", field: validation.field }, 400);
  const batch = validation.value;
  const installationLimit = await env.INSTALLATION_RATE_LIMITER.limit({ key: batch.installationID.toLowerCase() });
  if (!installationLimit.success) return jsonResponse({ error: "rate_limited" }, 429);

  const [installationHash, sessionHash] = await Promise.all([
    hmacHex(batch.installationID.toLowerCase(), env.INSTALLATION_HASH_KEY),
    hmacHex(batch.sessionID.toLowerCase(), env.INSTALLATION_HASH_KEY)
  ]);
  const statement = env.DB.prepare(`
    INSERT OR IGNORE INTO events (
      event_id, installation_id_hash, session_id_hash, event_name, occurred_at,
      app_version, build_number, platform, os_version, locale, properties_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  await env.DB.batch(batch.events.map((event) => statement.bind(
    event.id.toLowerCase(),
    installationHash,
    sessionHash,
    event.name,
    Date.parse(event.occurredAt),
    batch.context.appVersion,
    batch.context.buildNumber,
    batch.context.platform,
    batch.context.osVersion,
    batch.context.locale,
    JSON.stringify(event.properties ?? {})
  )));
  return jsonResponse({ accepted: batch.events.length }, 202);
}

type ValidationResult = { ok: true; value: AnalyticsBatch } | { ok: false; field: string };

function validateBatch(payload: unknown, now: number): ValidationResult {
  if (!isRecord(payload)) return invalid("body");
  if (payload.schemaVersion !== 1) return invalid("schemaVersion");
  if (payload.appID !== APP_ID) return invalid("appID");
  if (!isUUID(payload.installationID)) return invalid("installationID");
  if (!isUUID(payload.sessionID)) return invalid("sessionID");
  if (!isRecord(payload.context)) return invalid("context");
  const context = payload.context;
  if (!isBoundedString(context.appVersion, 1, 32)) return invalid("context.appVersion");
  if (!isBoundedString(context.buildNumber, 1, 32)) return invalid("context.buildNumber");
  if (typeof context.platform !== "string" || !PLATFORMS.has(context.platform)) return invalid("context.platform");
  if (!isBoundedString(context.osVersion, 1, 64)) return invalid("context.osVersion");
  if (!isBoundedString(context.locale, 1, 32)) return invalid("context.locale");
  if (!Array.isArray(payload.events) || payload.events.length < 1 || payload.events.length > MAX_EVENTS_PER_BATCH) {
    return invalid("events");
  }

  const events: AnalyticsEvent[] = [];
  for (let index = 0; index < payload.events.length; index += 1) {
    const candidate = payload.events[index];
    const prefix = `events[${index}]`;
    if (!isRecord(candidate)) return invalid(prefix);
    if (!isUUID(candidate.id)) return invalid(`${prefix}.id`);
    if (typeof candidate.name !== "string" || !EVENT_NAMES.has(candidate.name)) return invalid(`${prefix}.name`);
    if (typeof candidate.occurredAt !== "string") return invalid(`${prefix}.occurredAt`);
    const occurredAt = Date.parse(candidate.occurredAt);
    if (!Number.isFinite(occurredAt) || occurredAt < now - MAX_EVENT_AGE_MS || occurredAt > now + MAX_FUTURE_SKEW_MS) {
      return invalid(`${prefix}.occurredAt`);
    }
    const properties = validateProperties(candidate.properties, `${prefix}.properties`);
    if (!properties.ok) return properties;
    events.push({ id: candidate.id, name: candidate.name, occurredAt: candidate.occurredAt, properties: properties.value });
  }
  return {
    ok: true,
    value: {
      schemaVersion: 1,
      appID: APP_ID,
      installationID: payload.installationID,
      sessionID: payload.sessionID,
      context: {
        appVersion: context.appVersion,
        buildNumber: context.buildNumber,
        platform: context.platform,
        osVersion: context.osVersion,
        locale: context.locale
      },
      events
    }
  };
}

type PropertiesValidation = { ok: true; value: Record<string, string> } | { ok: false; field: string };

function validateProperties(value: unknown, field: string): PropertiesValidation {
  if (value === undefined) return { ok: true, value: {} };
  if (!isRecord(value)) return { ok: false, field };
  const entries = Object.entries(value);
  if (entries.length > 4) return { ok: false, field };
  const normalized: Record<string, string> = {};
  for (const [key, candidate] of entries) {
    if (!PROPERTY_KEYS.has(key) || typeof candidate !== "string") return { ok: false, field: `${field}.${key}` };
    if (key === "model_id" && !MODEL_ID_PATTERN.test(candidate)) return { ok: false, field: `${field}.${key}` };
    if (key === "category" && !CATEGORIES.has(candidate)) return { ok: false, field: `${field}.${key}` };
    if ((key === "animated" || key === "bundled") && !BOOLEANS.has(candidate)) return { ok: false, field: `${field}.${key}` };
    normalized[key] = candidate;
  }
  return { ok: true, value: normalized };
}

function invalid(field: string): ValidationResult {
  return { ok: false, field };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isUUID(value: unknown): value is string {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

function isBoundedString(value: unknown, minimum: number, maximum: number): value is string {
  return typeof value === "string" && value.length >= minimum && value.length <= maximum;
}

async function hmacHex(value: string, secret: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(value));
  return Array.from(new Uint8Array(signature), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      "referrer-policy": "no-referrer"
    }
  });
}
