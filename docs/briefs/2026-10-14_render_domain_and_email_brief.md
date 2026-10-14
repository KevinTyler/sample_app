# Brief for Claude in Chrome — Cordially: custom domain + real email (Resend) + Claude key

```
ORIENTATION / READ ORDER
1. You are in Kevin's Chrome. Cordially is already live on Render as the service "cordially"
   (https://cordially-0xet.onrender.com), deployed from render.yaml on GitHub branch
   claude/sharp-carson-ygmj9f, currently in TEST MODE (ENABLE_OUTBOX=1: nothing is really sent).
2. You will use three sites: the Render dashboard, Resend (resend.com — sends the app's email), and
   the DNS settings of Kevin's domain (wherever he manages it). Kevin does every sign-in, sign-up
   and secret himself; you do the navigation, non-secret settings, and DNS record copying.

WHY
Kevin wants to start testing Cordially with real people. That needs (a) the site on his own domain,
(b) email that really arrives (invitations, reply notices, password resets), sent from his domain so
it doesn't land in spam, and (c) the plain-language agent switched on. One increment: get those three
configured, turn test mode off with Kevin's OK, and prove a real email arrives.

TASK (one increment — stop when done)
0. ASK KEVIN FIRST (in chat), and wait for answers:
   - "Which domain should Cordially use?" (call it DOMAIN, e.g. example.com). Do NOT pick one
     yourself, and do NOT use the Legalbillcheck domain unless Kevin explicitly says so.
   - "Where is its DNS managed?" (registrar/DNS provider). If Kevin has no domain: STOP →
     BLOCKED: domain needed (never buy one).
   Plan to use two NEW subdomains: app.DOMAIN (the website) and invites.DOMAIN (sending email).

A. Website on app.DOMAIN
   1. Render → service "cordially" → Settings → Custom Domains → Add → app.DOMAIN.
      Note the target Render shows (a CNAME to cordially-0xet.onrender.com or similar).
   2. In Kevin's DNS provider (Kevin signs in), ADD a CNAME record: name "app", value = that target.
   3. Back in Render, click Verify. Wait until the domain shows verified and the certificate is
      issued (can take several minutes; if not verified after 30 minutes, report "waiting on DNS").
   4. Render → Environment: add APP_HOST = app.DOMAIN. (Don't save yet if you'll continue to B —
      batching saves means one redeploy. If the page saves immediately, that's fine.)

B. Email from invites.DOMAIN (Resend)
   1. Open https://resend.com. Kevin signs up or signs in himself — pause and wait for him.
   2. Resend → Domains → Add domain → invites.DOMAIN (default region).
   3. Resend shows several DNS records (typically MX + TXT/SPF for "send.invites", TXT/DKIM for
      "resend._domainkey.invites"). ADD each one in Kevin's DNS provider exactly as shown: type,
      name/host, value, priority. Copy values precisely (no added quotes or spaces).
   4. Back in Resend, click Verify DNS records. Wait for "Verified" (up to 30 minutes; otherwise
      report "waiting on DNS" and STOP here).
   5. KEVIN-ONLY STEP — pause and ask Kevin to do these himself (you must not read or type them):
      a. In Resend → API Keys → Create API key (permission: Sending access, domain invites.DOMAIN).
      b. In Render → cordially → Environment, set SMTP_PASSWORD = that API key.
      c. Optional, recommended: create a key at https://console.anthropic.com (API Keys; set a
         monthly spend limit under Billing/Limits) and set ANTHROPIC_API_KEY in Render the same way.
      Wait until Kevin says done.
   6. In Render → Environment set these (non-secret) values:
        SMTP_ADDRESS = smtp.resend.com
        SMTP_PORT    = 587
        SMTP_USERNAME = resend
        MAIL_FROM    = Cordially <invitations@invites.DOMAIN>
   7. TEST-MODE CHECKPOINT: ask Kevin "Turn on real sending? This deletes ENABLE_OUTBOX, so the app
      will email real people from now on." Only on an explicit yes: delete the ENABLE_OUTBOX variable.
   8. Save changes. Render redeploys; wait until the service shows Live again (a brief pause is normal).

C. Verify
   1. https://app.DOMAIN/up shows the green page; https://app.DOMAIN/ shows Cordially with a valid
      padlock (HTTPS).
   2. KEVIN-ONLY: Kevin signs up at https://app.DOMAIN/registration/new with his own email (or, if he
      already has an account there, uses "Forgot password?" on the sign-in page).
   3. Ask Kevin to then use "Forgot password?" with his email. In Resend → Emails, confirm a message to
      Kevin shows status Delivered, from invitations@invites.DOMAIN. Ask Kevin to confirm it arrived
      in his inbox (not spam) and that its link starts with https://app.DOMAIN.
   4. If ANTHROPIC_API_KEY was set: Kevin types "I'm planning a dinner for 8 next Friday at 7" on the
      Today page; expect a natural reply that names the dinner (not the step-by-step "What are we
      celebrating?" prompt).

CONSTRAINTS
- DNS: only ADD the records listed above. Never edit or delete existing records. If a record with the
  same name already exists, STOP and ask Kevin. Don't touch MX/SPF records for DOMAIN itself (Kevin's
  existing email must keep working) — Resend's records go on the invites subdomain only.
- Never read aloud, copy into chat, or type: passwords, API keys, OUTBOX_PASSWORD, SMTP_PASSWORD.
  Kevin handles sign-ins and secrets himself.
- No purchases (no domains, no paid plans). No sign-ups on Kevin's behalf.
- In Render: don't change plan, region, disk, branch, or any variable not named above. Don't delete
  ENABLE_OUTBOX without Kevin's explicit yes. Don't send invitations or messages to anyone.

ACCEPTANCE GATE (report each)
G1 Render shows app.DOMAIN verified with a certificate; https://app.DOMAIN/up is green.
G2 Resend shows invites.DOMAIN Verified.
G3 Render Environment has APP_HOST, SMTP_ADDRESS, SMTP_PORT, SMTP_USERNAME, MAIL_FROM set,
   SMTP_PASSWORD set by Kevin, and ENABLE_OUTBOX gone (only if Kevin said yes); service Live.
G4 Resend → Emails shows the password-reset email to Kevin as Delivered; Kevin confirms it arrived
   in his inbox with a link to https://app.DOMAIN.
G5 (if the Claude key was added) the Today page answers in natural language.
A failed or skipped gate is reported as FAILED/SKIPPED with what you saw — never as passed.

REPORT (≤ 15 lines)
STATUS: PASS | PARTIAL | BLOCKED
Domain: app.DOMAIN / invites.DOMAIN   DNS provider: <…>
DNS records added: <type name → value summary, no secrets>
G1–G5: one line each
Test mode: still on | off (Kevin approved at <time>)
BLOCKED: anything waiting on Kevin or DNS propagation
```
