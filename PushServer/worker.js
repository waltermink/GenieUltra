/**
 * GenieUltra Push Server — Cloudflare Worker
 *
 * Free push notifications without Apple Developer Program. Polls
 * themeparks.wiki every minute and fires notifications via ntfy.sh
 * and/or Telegram (whichever you configure — both also works for redundancy).
 *
 * Two entry points:
 *   - fetch()      → iOS app config sync + admin/debug endpoints
 *   - scheduled()  → cron-triggered every minute; polls and notifies
 *
 * KV bindings (single-user; one config stored):
 *   alerts:current             — JSON {waitAlerts, llAlerts, updatedAt}
 *   dedup:wait:<id>            — last-fired timestamp (1h TTL)
 *   dedup:ll:<id>:<prefix>     — last-fired returnStart (24h TTL)
 *   lastPoll                   — JSON {at, entityCount, error?}
 *
 * Secrets (wrangler secret put NAME):
 *   SHARED_SECRET              — random; iOS app + /admin/* auth header
 *   NTFY_TOPIC                 — your private ntfy.sh topic (also configured in ntfy iOS app)
 *   NTFY_AUTH                  — optional Bearer token if you protect ntfy topic auth
 *   TELEGRAM_BOT_TOKEN         — optional, from @BotFather
 *   TELEGRAM_CHAT_ID           — optional, your numeric chat ID
 *
 * Vars (wrangler.toml [vars]):
 *   PARK_ID                    — Magic Kingdom entity ID
 *   PARK_TIMEZONE              — IANA timezone, e.g. "America/New_York" (handles DST automatically)
 */

const COOLDOWN_WAIT_MS = 60 * 60 * 1000;       // 1 hour between wait-alert fires
const DEDUP_WAIT_TTL   = 60 * 60;              // 1 hour
const DEDUP_LL_TTL     = 24 * 60 * 60;         // 24 hours

export default {
  /** iOS-app + admin HTTP API */
  async fetch(request, env, ctx) {
    return handleFetch(request, env, ctx);
  },

  /** Cron — every minute per wrangler.toml [triggers] */
  async scheduled(controller, env, ctx) {
    ctx.waitUntil(runPoll(env));
  },
};

// ════════════════════════════════════════════════════════════════════════════
//  FETCH HANDLER
// ════════════════════════════════════════════════════════════════════════════

async function handleFetch(request, env, ctx) {
  const url = new URL(request.url);

  // CORS preflight (for browser-based debugging)
  if (request.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders() });
  }

  // Unauthenticated health check (so the app can verify URL before configuring auth)
  if (url.pathname === "/health" && request.method === "GET") {
    return json({
      ok: true,
      service: "genieultra-push",
      time: new Date().toISOString(),
      channels: configuredChannels(env),
    });
  }

  // Auth gate for everything else
  if (!env.SHARED_SECRET) {
    return json({ ok: false, error: "server missing SHARED_SECRET — run `wrangler secret put SHARED_SECRET`" }, 500);
  }
  const auth = request.headers.get("authorization") ?? "";
  if (auth !== `Bearer ${env.SHARED_SECRET}`) {
    return json({ ok: false, error: "unauthorized" }, 401);
  }

  try {
    // App endpoints
    if (url.pathname === "/sync-alerts" && request.method === "POST") return syncAlerts(request, env);
    if (url.pathname === "/test"        && request.method === "POST") return testPush(env);

    // Admin / debug endpoints — for Claude or curl to inspect & fix
    if (url.pathname === "/admin/state"        && request.method === "GET")  return adminState(env);
    if (url.pathname === "/admin/clear-dedup"  && request.method === "POST") return adminClearDedup(env);
    if (url.pathname === "/admin/poll-now"     && request.method === "POST") return adminPollNow(env);
    if (url.pathname === "/admin/test-fetch"   && request.method === "GET")  return adminTestFetch(env);

    return json({ ok: false, error: "not found" }, 404);
  } catch (e) {
    console.error("[fetch] handler error:", e.message, e.stack);
    return json({ ok: false, error: e.message }, 500);
  }
}

// ─── App-facing endpoints ─────────────────────────────────────────────────

async function syncAlerts(request, env) {
  let body;
  try { body = await request.json(); }
  catch { return json({ ok: false, error: "invalid json" }, 400); }

  const payload = {
    waitAlerts: Array.isArray(body.waitAlerts) ? body.waitAlerts : [],
    llAlerts:   Array.isArray(body.llAlerts)   ? body.llAlerts   : [],
    updatedAt:  new Date().toISOString(),
  };
  await env.ALERT_STATE.put("alerts:current", JSON.stringify(payload));
  return json({
    ok: true,
    counts: { wait: payload.waitAlerts.length, ll: payload.llAlerts.length },
  });
}

async function testPush(env) {
  const channels = configuredChannels(env);
  if (channels.length === 0) {
    return json({ ok: false, error: "no notification channels configured" }, 500);
  }
  await sendNotifications(env, {
    title: "GenieUltra push test",
    body:  "Worker is reachable and notification channels are working.",
    tags:  ["white_check_mark"],
    priority: 4,
  });
  return json({ ok: true, channels });
}

// ─── Admin endpoints ─────────────────────────────────────────────────────

async function adminState(env) {
  const alertsRaw  = await env.ALERT_STATE.get("alerts:current");
  const lastPoll   = await env.ALERT_STATE.get("lastPoll");
  const dedupList  = await env.ALERT_STATE.list({ prefix: "dedup:" });

  return json({
    ok: true,
    channels: configuredChannels(env),
    parkID:   env.PARK_ID,
    timeZone: parkTimeZone(env),
    alerts:   alertsRaw  ? JSON.parse(alertsRaw)  : null,
    lastPoll: lastPoll   ? JSON.parse(lastPoll)   : null,
    dedupKeys: dedupList.keys.map((k) => k.name),
    now: new Date().toISOString(),
  });
}

async function adminClearDedup(env) {
  const list = await env.ALERT_STATE.list({ prefix: "dedup:" });
  for (const key of list.keys) await env.ALERT_STATE.delete(key.name);
  return json({ ok: true, cleared: list.keys.length });
}

async function adminPollNow(env) {
  await runPoll(env);
  const lastPoll = await env.ALERT_STATE.get("lastPoll");
  return json({ ok: true, lastPoll: lastPoll ? JSON.parse(lastPoll) : null });
}

async function adminTestFetch(env) {
  // Verify connectivity to themeparks.wiki without doing alert evaluation
  try {
    const resp = await fetch(
      `https://api.themeparks.wiki/v1/entity/${env.PARK_ID}/live`,
      { headers: { "User-Agent": "GenieUltra/1.0" } }
    );
    if (!resp.ok) return json({ ok: false, status: resp.status }, 502);
    const data = await resp.json();
    return json({
      ok: true,
      status: resp.status,
      entityCount: data.liveData?.length ?? 0,
      sample: (data.liveData ?? []).slice(0, 5).map((e) => ({ id: e.id, name: e.name, status: e.status })),
    });
  } catch (e) {
    return json({ ok: false, error: e.message }, 502);
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SCHEDULED POLL
// ════════════════════════════════════════════════════════════════════════════

async function runPoll(env) {
  // 1. Read alert config
  const alertsRaw = await env.ALERT_STATE.get("alerts:current");
  if (!alertsRaw) {
    console.log("[poll] no alerts configured yet");
    return;
  }
  let alerts;
  try { alerts = JSON.parse(alertsRaw); }
  catch (e) { console.error("[poll] bad alerts JSON:", e.message); return; }

  // Defensive: tolerate manually-edited KV state
  const waitAlerts = Array.isArray(alerts.waitAlerts) ? alerts.waitAlerts : [];
  const llAlerts   = Array.isArray(alerts.llAlerts)   ? alerts.llAlerts   : [];
  if (waitAlerts.length === 0 && llAlerts.length === 0) return;

  // 2. Fetch park live data
  let liveData;
  try {
    const resp = await fetch(
      `https://api.themeparks.wiki/v1/entity/${env.PARK_ID}/live`,
      { headers: { "User-Agent": "GenieUltra/1.0" } }
    );
    if (!resp.ok) {
      console.error("[poll] themeparks.wiki returned", resp.status);
      await recordLastPoll(env, { error: `themeparks ${resp.status}` });
      return;
    }
    ({ liveData } = await resp.json());
  } catch (e) {
    console.error("[poll] fetch error:", e.message);
    await recordLastPoll(env, { error: `fetch: ${e.message}` });
    return;
  }

  if (!Array.isArray(liveData)) {
    console.error("[poll] themeparks.wiki response had no liveData array");
    await recordLastPoll(env, { error: "response missing liveData" });
    return;
  }

  await recordLastPoll(env, { entityCount: liveData.length });

  // 3. Evaluate wait-time alerts
  const now = Date.now();
  for (const alert of waitAlerts) {
    try { await evaluateWaitAlert(alert, liveData, now, env); }
    catch (e) { console.error("[poll] wait alert", alert?.attractionID, "failed:", e.message); }
  }

  // 4. Evaluate Lightning Lane alerts
  for (const alert of llAlerts) {
    try { await evaluateLLAlert(alert, liveData, env); }
    catch (e) { console.error("[poll] LL alert", alert?.attractionID, "failed:", e.message); }
  }
}

async function evaluateWaitAlert(alert, liveData, now, env) {
  const entity = liveData.find((e) => e.id === alert.attractionID);
  if (!entity) return;

  const cooldownKey = `dedup:wait:${alert.attractionID}`;
  const lastFired = Number((await env.ALERT_STATE.get(cooldownKey)) ?? "0");
  if (now - lastFired < COOLDOWN_WAIT_MS) return;

  if (alert.type === "isOperating") {
    const wait = entity.queue?.STANDBY?.waitTime;
    if (entity.status === "OPERATING" && wait != null) {
      await sendNotifications(env, {
        title: `${entity.name} is now operating`,
        body:  `Current wait: ${wait} min`,
        tags:  ["rocket"],
        priority: 4,
      });
      await env.ALERT_STATE.put(cooldownKey, String(now), { expirationTtl: DEDUP_WAIT_TTL });
    }
  } else if (alert.type === "threshold" && typeof alert.threshold === "number") {
    const wait = entity.queue?.STANDBY?.waitTime;
    if (wait != null && wait <= alert.threshold) {
      await sendNotifications(env, {
        title: `Wait time low: ${entity.name}`,
        body:  `Current wait ${wait} min (threshold ≤ ${alert.threshold})`,
        tags:  ["hourglass_flowing_sand"],
        priority: 4,
      });
      await env.ALERT_STATE.put(cooldownKey, String(now), { expirationTtl: DEDUP_WAIT_TTL });
    }
  }
}

async function evaluateLLAlert(alert, liveData, env) {
  const entity = liveData.find((e) => e.id === alert.attractionID);
  if (!entity) return;

  const tz = parkTimeZone(env);

  const evalQueue = async (queueKey, prefix, label) => {
    const queue = entity.queue?.[queueKey];
    if (!queue || queue.state !== "AVAILABLE" || !queue.returnStart) return;

    const localHour = localHourFor(queue.returnStart, tz);
    if (localHour == null) return;
    if (localHour < alert.windowStartHour || localHour > alert.windowEndHour) return;

    const dedupKey = `dedup:ll:${alert.attractionID}:${prefix}`;
    const lastReturnStart = await env.ALERT_STATE.get(dedupKey);
    if (lastReturnStart === queue.returnStart) return;

    const timeStr = formatLocalTime(queue.returnStart, tz);
    await sendNotifications(env, {
      title: `${label} available: ${entity.name}`,
      body:  `Return ${timeStr}`,
      tags:  ["zap"],
      priority: 5, // max urgency — LL is time-critical
    });
    await env.ALERT_STATE.put(dedupKey, queue.returnStart, { expirationTtl: DEDUP_LL_TTL });
  };

  if (alert.includeStandardLL)    await evalQueue("RETURN_TIME",      "standard", "Lightning Lane");
  if (alert.includePremierAccess) await evalQueue("PAID_RETURN_TIME", "paid",     "Lightning Lane+");
}

async function recordLastPoll(env, extra) {
  await env.ALERT_STATE.put("lastPoll", JSON.stringify({
    at: new Date().toISOString(),
    ...extra,
  }));
}

// ════════════════════════════════════════════════════════════════════════════
//  NOTIFICATION CHANNELS
// ════════════════════════════════════════════════════════════════════════════

function configuredChannels(env) {
  const channels = [];
  if (env.NTFY_TOPIC) channels.push("ntfy");
  if (env.TELEGRAM_BOT_TOKEN && env.TELEGRAM_CHAT_ID) channels.push("telegram");
  return channels;
}

/**
 * Dispatch to every configured channel. Failures in one channel don't block others.
 */
async function sendNotifications(env, message) {
  const tasks = [];
  if (env.NTFY_TOPIC) tasks.push(sendNtfy(env, message));
  if (env.TELEGRAM_BOT_TOKEN && env.TELEGRAM_CHAT_ID) tasks.push(sendTelegram(env, message));

  if (tasks.length === 0) {
    console.error("[notify] no channels configured — message dropped:", message.title);
    return;
  }
  await Promise.allSettled(tasks);
}

async function sendNtfy(env, { title, body, tags, priority, click }) {
  const payload = {
    topic:    env.NTFY_TOPIC,
    title,
    message:  body,
    priority: priority ?? 3,
    tags:     tags ?? [],
  };
  if (click) payload.click = click;

  const headers = { "content-type": "application/json" };
  if (env.NTFY_AUTH) headers.authorization = `Bearer ${env.NTFY_AUTH}`;

  try {
    const resp = await fetch("https://ntfy.sh/", {
      method: "POST",
      headers,
      body: JSON.stringify(payload),
    });
    if (!resp.ok) {
      console.error(`[ntfy] ${resp.status}:`, await resp.text());
    } else {
      console.log(`[ntfy] sent "${title}"`);
    }
  } catch (e) {
    console.error("[ntfy] request error:", e.message);
  }
}

async function sendTelegram(env, { title, body }) {
  // Telegram's HTML mode is the safest — only need to escape < > &
  const text = `<b>${escapeHTML(title)}</b>\n${escapeHTML(body)}`;
  const url = `https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`;
  try {
    const resp = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        chat_id: env.TELEGRAM_CHAT_ID,
        text,
        parse_mode: "HTML",
      }),
    });
    if (!resp.ok) {
      console.error(`[telegram] ${resp.status}:`, await resp.text());
    } else {
      console.log(`[telegram] sent "${title}"`);
    }
  } catch (e) {
    console.error("[telegram] request error:", e.message);
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Helpers
// ════════════════════════════════════════════════════════════════════════════

function json(data, status = 200) {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: { "content-type": "application/json", ...corsHeaders() },
  });
}

function corsHeaders() {
  return {
    "access-control-allow-origin":  "*",
    "access-control-allow-methods": "GET, POST, OPTIONS",
    "access-control-allow-headers": "authorization, content-type",
  };
}

function escapeHTML(s) {
  return String(s).replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c]));
}

function parkTimeZone(env) {
  return env.PARK_TIMEZONE || "America/New_York";
}

function formatLocalTime(iso, tz) {
  try {
    return new Date(iso).toLocaleTimeString("en-US", {
      hour: "numeric",
      minute: "2-digit",
      timeZone: tz,
    });
  } catch {
    // Fallback to UTC if the env timezone is invalid
    return new Date(iso).toUTCString();
  }
}

function localHourFor(iso, tz) {
  try {
    const f = new Intl.DateTimeFormat("en-US", {
      hour:    "numeric",
      hour12:  false,
      timeZone: tz,
    });
    const parts = f.formatToParts(new Date(iso));
    const hour = parts.find((p) => p.type === "hour")?.value;
    if (hour == null) return null;
    const n = Number(hour);
    // "24" represents midnight on some locales — normalize to 0
    return n === 24 ? 0 : n;
  } catch {
    return null;
  }
}
