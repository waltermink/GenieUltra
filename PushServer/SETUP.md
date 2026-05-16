# GenieUltra Push Server — Complete Setup Guide

Real-time Lightning Lane & wait-time alerts. **No Apple Developer Program required, $0/month forever.**

The Worker polls themeparks.wiki every minute and pushes notifications through **ntfy.sh** (and/or **Telegram**) — both are free services that handle iOS notification delivery via their own apps.

Time budget: **~25 minutes** if you've never used Cloudflare Workers before. **~10 minutes** if you have. Follow top-to-bottom.

## Architecture

```
┌────────────────┐     ┌─────────────────────┐     ┌───────────────────────┐
│  iOS app       │ ──► │ Cloudflare Worker   │     │  themeparks.wiki API  │
│  (Settings →   │     │  • /sync-alerts     │ ──► │                       │
│   Push Server) │     │  • cron every 1 min │ ◄── │                       │
└────────────────┘     │  • POST to ntfy/tg  │     └───────────────────────┘
                       └─────────┬───────────┘
                                 │
                       ┌─────────┴───────────┐
                       │                     │
                  ┌────▼──────┐      ┌───────▼─────┐
                  │  ntfy.sh  │      │  Telegram   │
                  │  (free)   │      │  (free)     │
                  └────┬──────┘      └──────┬──────┘
                       │                    │
                  ┌────▼──────────┐    ┌────▼──────────┐
                  │  ntfy iOS app │    │ Telegram app  │
                  │  on your phone│    │ on your phone │
                  └───────────────┘    └───────────────┘
```

You can configure **just ntfy**, **just Telegram**, or **both for redundancy**. Both for redundancy is recommended — if one service has an outage, you still get notifications.

---

## Prerequisites

- macOS with Xcode installed
- Node.js 18+ (`node -v` to verify)
- An iPhone
- A Cloudflare account (free, sign up at [dash.cloudflare.com/sign-up](https://dash.cloudflare.com/sign-up) — takes 30 seconds, only needs email)

**You do NOT need:** Apple Developer Program, paid services, a credit card.

---

## Step 1 — Pick your notification channels

You need **at least one** of these. Setting up both is highly recommended for reliability.

### Option A — ntfy.sh (simplest, 2 minutes)

1. Install the [ntfy app from the App Store](https://apps.apple.com/us/app/ntfy/id1625396347)
2. Open the app → tap **+** → **Subscribe to topic**
3. **Topic name**: pick something secret and hard to guess. Example: `genieultra-walter-9k3p2j7t`. The topic name IS your password — anyone who knows it can send you notifications. Don't use a common word.
4. Tap **Subscribe**
5. Test it manually from your laptop:
   ```bash
   curl -d "It works!" ntfy.sh/your-topic-name-here
   ```
   Your phone should buzz within a second.
6. **Save the topic name** — you'll paste it into a Cloudflare secret in Step 3.

### Option B — Telegram (most reliable, 5 minutes)

1. Open Telegram on your phone, search for **@BotFather**, start a chat
2. Send `/newbot`
3. Pick a display name (e.g. `GenieUltra Alerts`)
4. Pick a username ending in `bot` (e.g. `genieultra_walter_bot`)
5. **Copy the HTTP API token** BotFather sends you. Looks like `7234567890:AAH...`. **Save it.**
6. Send any message to your new bot (anything works, e.g. "hello"). This is required — bots can't message you until you message them first.
7. Get your chat ID. Open this URL in any browser, replacing `<TOKEN>` with your bot's token:
   ```
   https://api.telegram.org/bot<TOKEN>/getUpdates
   ```
   Find `"chat":{"id":123456789,...` in the response. **That number is your chat ID.** Save it.

Verify both work:
```bash
curl -X POST \
  -d "chat_id=<YOUR_CHAT_ID>&text=It works" \
  https://api.telegram.org/bot<YOUR_TOKEN>/sendMessage
```
Your Telegram app should show the message instantly.

---

## Step 2 — Find your Magic Kingdom park ID

```bash
curl -s "https://api.themeparks.wiki/v1/destinations" | \
  python3 -c "
import sys, json
data = json.load(sys.stdin)
wdw = next(d for d in data['destinations'] if d['slug'] == 'waltdisneyworldresort')
for p in wdw['parks']:
    print(p['id'], p['name'])
"
```

Copy the ID next to `Magic Kingdom Park`. You'll paste it into `wrangler.toml`.

---

## Step 3 — Deploy the Cloudflare Worker

This is the only "real" infrastructure step. ~15 minutes the first time you do it. Once deployed it runs forever for free.

### 3a. Make a Cloudflare account (skip if you already have one)

1. Go to [dash.cloudflare.com/sign-up](https://dash.cloudflare.com/sign-up)
2. Email + password. **No credit card needed.**
3. Verify your email when their confirmation arrives
4. You'll land on the Cloudflare dashboard — leave that browser tab open, you'll come back to it

### 3b. Install Wrangler (Cloudflare's CLI)

Open Terminal on your Mac.

```bash
# Check Node.js is installed (need 18 or newer)
node --version
```

If you see `v18.x`, `v20.x`, or higher, you're good. If `command not found` or older, install Node first: `brew install node` (takes ~2 min).

Install Wrangler globally:

```bash
npm install -g wrangler
```

That command might print a bunch of deprecation warnings — ignore them. Verify it installed:

```bash
wrangler --version
```

You should see something like `⛅️ wrangler 4.x.x`.

### 3c. Log Wrangler in to your Cloudflare account

```bash
wrangler login
```

This pops open your browser to a Cloudflare auth page. Click **Allow** on the permissions screen. The browser will say "successfully logged in"; you can close that tab.

Back in Terminal, you'll see:
```
Successfully logged in.
```

Verify it picked up your account:
```bash
wrangler whoami
```
You should see your email + your account ID.

### 3d. Move into the PushServer directory

```bash
cd "/Users/wwmink/GitHub Repos/GenieUltra/.claude/worktrees/elastic-nightingale-339c08/PushServer"
```

> The path above is the worktree; if you've merged to your main branch, use that path instead. From here on every `wrangler` command needs to run from this directory because Wrangler reads `wrangler.toml` from the current directory.

### 3e. Create the KV namespace

KV (Key-Value) is Cloudflare's distributed key-value store. Your Worker uses it to remember the alert config across cron runs and to dedupe notifications.

```bash
wrangler kv namespace create ALERT_STATE
```

Output looks like:
```
🌀 Creating namespace with title "genieultra-push-ALERT_STATE"
✨ Success!
Add the following to your configuration file in your kv_namespaces array:
{ binding = "ALERT_STATE", id = "abcd1234ef5678..." }
```

**Copy the `id` value** (the long hex string after `id = "`). You need to paste it into `wrangler.toml`.

Open `wrangler.toml` in any editor:
```bash
open -e wrangler.toml          # opens in TextEdit
# or: code wrangler.toml       # VS Code
# or: nano wrangler.toml       # in-terminal editor
```

Find this block:
```toml
[[kv_namespaces]]
binding = "ALERT_STATE"
id      = "REPLACE_WITH_YOUR_KV_NAMESPACE_ID"
```

Replace the placeholder with the id you copied. Save the file.

Also update the `[vars]` block (using the Magic Kingdom park ID you found in Step 2):
```toml
[vars]
PARK_ID       = "75ea578a-adc8-4116-a54d-dccb60765ef9"   # ← paste your park ID
PARK_TIMEZONE = "America/New_York"
```

(That UUID is the actual Magic Kingdom ID as of writing, but verify against your Step 2 output in case themeparks.wiki ever changes it.)

### 3f. Generate a shared secret

This is the password the iOS app sends to authorize itself to your Worker. Anything random and long enough — generate one with:

```bash
openssl rand -hex 32
```

You'll get something like:
```
9f2a8b3c4d5e6f7081a2b3c4d5e6f70819a2b3c4d5e6f70811234567890abcdef
```

**Copy this string.** You'll paste it into Wrangler in the next step AND into the iOS app's Settings later. Save it somewhere — your password manager, Notes, etc.

### 3g. Set the Wrangler secrets

Secrets are encrypted environment variables that your Worker can read but that don't appear in `wrangler.toml`. Each one is set interactively:

```bash
wrangler secret put SHARED_SECRET
```

Wrangler will print:
```
✔ Enter a secret value: › 
```

Paste the hex string from 3f and press Enter. Wrangler responds:
```
✨ Success! Uploaded secret SHARED_SECRET
```

Now set the notification channel secrets. **You need at least one channel** — ntfy.sh is the simpler path, Telegram is more reliable, both works as redundancy.

**If you set up ntfy in Step 1A:**
```bash
wrangler secret put NTFY_TOPIC
```
Paste your topic name (the exact string you typed when subscribing in the ntfy iOS app, e.g. `genieultra-walter-9k3p2j7t`).

**If you set up Telegram in Step 1B:**
```bash
wrangler secret put TELEGRAM_BOT_TOKEN
```
Paste the BotFather token (`7234567890:AAH...`).

```bash
wrangler secret put TELEGRAM_CHAT_ID
```
Paste your numeric chat ID.

Verify which secrets are set:
```bash
wrangler secret list
```
You should see entries for each secret you just put. Values aren't shown (that's the point of secrets).

### 3h. Deploy

```bash
wrangler deploy
```

Output looks like:
```
⛅️ wrangler 4.x.x
-------------------
Total Upload: 5.32 KiB / gzip: 1.89 KiB
Worker Startup Time: 12 ms
Your worker has access to the following bindings:
- KV Namespaces:
  - ALERT_STATE: abcd1234ef5678...
- Vars:
  - PARK_ID: "75ea578a-adc8-4116-a54d-dccb60765ef9"
  - PARK_TIMEZONE: "America/New_York"
Uploaded genieultra-push (1.23 sec)
Deployed genieultra-push triggers (0.41 sec)
  https://genieultra-push.YOUR_SUBDOMAIN.workers.dev
  schedule: * * * * *
Current Version ID: 12345678-...
```

**Copy the `https://genieultra-push.YOUR_SUBDOMAIN.workers.dev` URL.** You'll paste it into the iOS app's Settings shortly. `YOUR_SUBDOMAIN` is the Cloudflare-issued subdomain tied to your account (usually based on your email).

### 3i. Verify in the Cloudflare dashboard (optional but reassuring)

Go to [dash.cloudflare.com](https://dash.cloudflare.com), pick your account, then **Compute (Workers)** → **Workers & Pages** in the left sidebar. You should see `genieultra-push` listed.

Click it → **Settings** tab → **Triggers** subsection. You should see a Cron Trigger row showing `* * * * *` (every minute). If it says "no triggers", something went wrong with the deploy — re-run `wrangler deploy`.

Click the **Bindings** subsection. You should see the `ALERT_STATE` KV namespace listed, and your secrets + vars.

### 3j. Smoke test from your Mac

The unauthenticated `/health` endpoint is the quickest way to verify the Worker is responding:

```bash
curl https://genieultra-push.YOUR_SUBDOMAIN.workers.dev/health
```

Expected output:
```json
{
  "ok": true,
  "service": "genieultra-push",
  "time": "2026-05-16T...",
  "channels": ["ntfy"]
}
```

If `channels` is `[]`, you didn't set NTFY_TOPIC (or didn't set both TELEGRAM_* secrets) — go back to 3g.

Now do a real end-to-end test. The `/test` endpoint requires auth:

```bash
# Replace both placeholders below
WORKER_URL="https://genieultra-push.YOUR_SUBDOMAIN.workers.dev"
SECRET="paste-your-shared-secret-from-3f"

curl -X POST -H "Authorization: Bearer $SECRET" "$WORKER_URL/test"
```

Within ~2 seconds your iOS ntfy app (and/or Telegram) should show a test notification "GenieUltra push test". If you got the notification, **the entire backend works**. You're done with this step.

### 3k. Watch the cron run live (optional)

In a separate Terminal tab:
```bash
cd "/Users/wwmink/GitHub Repos/GenieUltra/.claude/worktrees/elastic-nightingale-339c08/PushServer"
wrangler tail
```

`wrangler tail` streams the Worker's logs in real time. Within 60 seconds you'll see a `[poll] no alerts configured yet` line — that's the cron firing. Once you sync alerts from the iOS app, you'll see `[poll]` lines with actual evaluations. Press Ctrl-C to exit.

### 3l. Common errors at this stage

| Symptom | Fix |
|---|---|
| `wrangler login` opens browser but says "session expired" | Try `wrangler logout && wrangler login` |
| `wrangler deploy` says "missing API token" | Run `wrangler login` again |
| `wrangler deploy` says "kv namespace not found" | The id in `wrangler.toml` doesn't match what 3e printed — re-paste |
| Deploy succeeds but `/health` returns 404 | DNS hasn't propagated yet, wait 30 seconds and retry |
| Deploy succeeds but cron isn't running (no `[poll]` lines in `wrangler tail`) | Check Triggers in the dashboard. If empty, re-run `wrangler deploy` |
| `/health` says `channels: []` | Re-run `wrangler secret put NTFY_TOPIC` and/or both TELEGRAM_* secrets |
| Anything else weird | `wrangler tail` will show the actual error |

---

## Step 4 — Connect the iOS app

1. Build & run the app from Xcode on any iOS simulator or real device. **No special capabilities needed** — push notifications go through ntfy/Telegram, not APNS.
2. Open **Settings** tab → **Push Server (Cloudflare)** section
3. Worker URL: paste from Step 3e (e.g. `https://genieultra-push.YOUR_SUBDOMAIN.workers.dev`)
4. Shared secret: paste from Step 3c
5. Tap **Save & Sync**
6. Status row should change to ✅ **Connected — Last sync just now**
7. Tap **Send test push**. Your phone should buzz within ~1 second from ntfy (and/or Telegram).

If the test push works, **you're done with setup**. Move to Step 5.

---

## Step 5 — Create your alerts

From here it's the normal app flow:

1. **Alerts tab** → **+** → create wait-time and Lightning Lane alerts
2. Every change automatically resyncs to the Worker (watch the Settings status row blink "Syncing…" → "Connected")
3. Cron evaluates conditions every minute. When matched, push fires immediately

You can close the app entirely. Notifications arrive on the Lock Screen from the ntfy and/or Telegram apps.

---

## Step 6 — (Optional) Wire up Claude for remote debugging

If something breaks during the day at the park, you want to be able to ask Claude Code to diagnose and fix it from your phone. Two complementary mechanisms:

### 6a. Save the worker URL + secret for Claude

Create `~/.genieultra-worker.env` on your laptop (or in your phone's notes — somewhere Claude can read):

```
GENIEULTRA_WORKER_URL=https://genieultra-push.YOUR_SUBDOMAIN.workers.dev
GENIEULTRA_SHARED_SECRET=<the hex string from 3c>
```

Now you can ask Claude things like:

> Curl the worker's /admin/state and tell me why my Pirates LL alert isn't firing.

And Claude can run:
```bash
source ~/.genieultra-worker.env
curl -H "Authorization: Bearer $GENIEULTRA_SHARED_SECRET" \
     "$GENIEULTRA_WORKER_URL/admin/state" | jq
```

Admin endpoints available:
- `GET /admin/state` — current alert config, dedup state, last poll info, configured channels
- `POST /admin/clear-dedup` — clears dedup state (useful if you want to re-fire an alert)
- `POST /admin/poll-now` — triggers an immediate poll (don't wait for the cron)
- `GET /admin/test-fetch` — verifies the Worker can reach themeparks.wiki
- `POST /test` — fires a test notification through all configured channels

All require the `Authorization: Bearer <secret>` header.

### 6b. (Optional, more powerful) Cloudflare MCP server

Cloudflare publishes an official MCP server that gives Claude full read/write access to your Workers, KV namespaces, secrets, and logs. This lets Claude make code changes and redeploy without your laptop being involved.

1. In Claude Code, install the Cloudflare API MCP server. Add to `~/.claude/settings.json`:
   ```json
   {
     "mcpServers": {
       "cloudflare": {
         "url": "https://mcp.cloudflare.com/mcp"
       }
     }
   }
   ```
2. Run `/mcp` in Claude Code to authorize via OAuth — it opens a browser, you click approve, done.
3. Now Claude can run `wrangler` commands, edit KV, read logs, redeploy on your behalf.

For headless/API-token use (no OAuth):

1. Create a [Cloudflare API token](https://dash.cloudflare.com/profile/api-tokens) with permissions:
   - **Workers Scripts:Edit** (to deploy fixes)
   - **Workers KV Storage:Edit** (to inspect/edit state)
   - **Workers Tail:Read** (to read logs)
   - Scope it to **your account** (not all accounts)
2. Save the token securely (1Password, etc.)
3. When you need Claude to act, paste the token + `wrangler --api-token=<TOKEN> ...` invocation.

The admin endpoints in 6a work without any of this — they're the lightweight option. The MCP setup is for "Claude, deploy a hotfix" workflows.

---

## Verification checklist

Before you put your laptop away tonight, run through this checklist:

- [ ] `curl https://your-worker.workers.dev/health` returns `{"ok":true,...}` with `channels` listing ntfy and/or telegram
- [ ] iOS Settings → Push Server shows ✅ **Connected**
- [ ] Tap **Send test push** in iOS Settings — phone gets a notification within a few seconds
- [ ] Add a guaranteed-to-fire test alert (e.g. wait-time threshold ≤ 999 min on any operating ride). Within 1 minute you should receive a real notification from the cron job, not a manual test
- [ ] `wrangler tail` shows a `[ntfy] sent ...` or `[telegram] sent ...` line each time a push fires
- [ ] If you configured both channels, both apps receive the test push (proves redundancy)

---

## Troubleshooting

### iOS app shows "Server returned 401: unauthorized"

Shared secret mismatch. Run `wrangler secret put SHARED_SECRET` again with the exact same value you pasted into the iOS app. Or copy fresh value from Wrangler to the app.

### `curl /health` works but `/sync-alerts` returns 401

Same fix as above — `/health` is unauthenticated by design, everything else requires the secret.

### ntfy notifications never arrive

1. Manual test from terminal: `curl -d "test" ntfy.sh/YOUR_TOPIC_NAME`
2. If THIS doesn't notify your phone, the ntfy app isn't subscribed correctly. Re-add the subscription in the app.
3. If manual test works but cron doesn't, check `wrangler tail` — likely the `NTFY_TOPIC` secret was set wrong. Run `wrangler secret put NTFY_TOPIC` again.

### Telegram notifications never arrive

1. Verify the bot token: `curl https://api.telegram.org/bot<TOKEN>/getMe` — should return your bot info.
2. Verify the chat ID: visit `https://api.telegram.org/bot<TOKEN>/getUpdates` and check the `chat.id` value.
3. If both work but cron doesn't deliver, check `wrangler tail` for the `[telegram] error` line — it tells you exactly what went wrong (usually a wrong token or chat ID).

### `wrangler tail` shows cron running but no notifications fire

The most likely cause is that no alerts are stored. Run:
```bash
source ~/.genieultra-worker.env  # if you set this up in 6a
curl -H "Authorization: Bearer $GENIEULTRA_SHARED_SECRET" \
     "$GENIEULTRA_WORKER_URL/admin/state"
```
Look at `alerts` field — if it's `null`, the app hasn't synced any alerts. Open the app's Alerts tab, ensure at least one alert exists and is **toggled on**, then watch the Settings status row sync.

### Notifications arrive but the return time is wrong by an hour

The Worker uses `PARK_TIMEZONE = "America/New_York"` which handles DST automatically — you shouldn't see this. If you do, confirm `wrangler.toml` has the right IANA timezone (`America/New_York` for WDW, year-round). Then `wrangler deploy`.

### Cron isn't running at all

```bash
# Should list the cron trigger
wrangler triggers list
```
If empty, your `wrangler deploy` didn't pick up the `[triggers]` block. Confirm `wrangler.toml` has `crons = ["* * * * *"]` and redeploy.

### Worker logs show "no alerts configured yet" every minute

The iOS app hasn't successfully synced. Open Settings → Push Server, tap **Save & Sync**, watch for the status to go ✅ Connected. If it errors, the error message tells you what's wrong (usually wrong URL or wrong secret).

### The app fires duplicate notifications

The Worker has 1-hour cooldown on wait alerts and per-return-time dedup on LL alerts. If you somehow get duplicates, run:
```bash
curl -X POST -H "Authorization: Bearer $GENIEULTRA_SHARED_SECRET" \
     "$GENIEULTRA_WORKER_URL/admin/clear-dedup"
```
This wipes all dedup state. The next cron run will treat everything as new.

---

## Cost summary

| Item | Monthly cost |
|---|---|
| Cloudflare Workers Free | $0 |
| Cloudflare Workers KV Free (100K reads, 1K writes/day) | $0 |
| ntfy.sh public service | $0 |
| Telegram Bot API | $0 |
| themeparks.wiki API | $0 |
| **Total** | **$0** |

Free-tier limits are far beyond what this workload uses (cron does ~1440 reads/day, fires < 50 writes/day on a busy park day).

---

## Quick reference: useful commands

```bash
# Logs (live)
wrangler tail

# Current worker state
curl -H "Authorization: Bearer $SHARED_SECRET" \
     "$WORKER_URL/admin/state" | jq

# Force a poll right now
curl -X POST -H "Authorization: Bearer $SHARED_SECRET" \
     "$WORKER_URL/admin/poll-now"

# Reset all dedup state (will re-fire alerts that were already sent)
curl -X POST -H "Authorization: Bearer $SHARED_SECRET" \
     "$WORKER_URL/admin/clear-dedup"

# Test themeparks.wiki reachability from the worker
curl -H "Authorization: Bearer $SHARED_SECRET" \
     "$WORKER_URL/admin/test-fetch" | jq

# Test push delivery to all configured channels
curl -X POST -H "Authorization: Bearer $SHARED_SECRET" \
     "$WORKER_URL/test"

# Update a secret
wrangler secret put SECRET_NAME

# Redeploy after editing worker.js
wrangler deploy
```
