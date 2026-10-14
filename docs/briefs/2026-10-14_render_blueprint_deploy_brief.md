# Brief for Claude in Chrome — deploy Cordially to Render (test mode)

```
ORIENTATION / READ ORDER
1. You are working in Kevin's Chrome, signed in to his own accounts. Use only the Render dashboard
   (https://dashboard.render.com) and, if Render asks, GitHub's "install/authorize Render" screens.
2. The deployment is defined by render.yaml at the root of GitHub repo KevinTyler/sample_app on branch
   claude/sharp-carson-ygmj9f. It is the source of truth: do not change any setting it defines in the
   Render UI. If what Render shows differs from the expectations below, stop and report.

WHY
Kevin wants Cordially (an invitations app) running on Render so he can start testing it. It deploys
in TEST MODE: no email or text is ever really sent — everything is captured at /dev/outbox behind a
password. One increment: get the Blueprint applied, the service Live, and prove it works.

TASK (one increment — stop when done)
1. Open https://dashboard.render.com. Confirm you are signed in. If not, STOP → BLOCKED: sign-in.
2. Click "New" → "Blueprint" (or open https://dashboard.render.com/blueprints and click
   "New Blueprint Instance").
3. Connect the repository KevinTyler/sample_app.
   - If Render asks to connect/configure GitHub: choose "Only select repositories" and grant ONLY
     KevinTyler/sample_app. Do not grant access to all repositories.
4. On the Blueprint form:
   - Blueprint name: cordially
   - Branch: claude/sharp-carson-ygmj9f   (NOT main — render.yaml is only on this branch)
   - Blueprint path: render.yaml (the default)
5. Check the preview Render shows. Expected, exactly:
   - 1 web service named "cordially", runtime Ruby, plan Starter, region Oregon
   - 1 disk "cordially-storage", 5 GB, mount path /opt/render/project/src/storage
   If Render shows a render.yaml error or anything different, copy the exact message and STOP.
6. Render will ask for values for: MAIL_FROM, SMTP_ADDRESS, SMTP_USERNAME, SMTP_PASSWORD,
   ANTHROPIC_API_KEY. Leave ALL of them blank. If Render refuses a blank value, STOP and report which
   field (do not invent a value).
7. COST CHECKPOINT — before clicking "Apply" / "Deploy Blueprint":
   - Read the monthly cost Render shows (web service + disk).
   - Ask Kevin in the chat: "Render will charge <amount>/month for the Starter web service and the 5 GB
     disk. Apply?" Wait for an explicit yes.
   - If Render asks for a payment method, STOP — Kevin enters card details himself.
8. After Kevin says yes, click Apply. Open the "cordially" service and watch Events/Logs until the
   status is "Live" (allow up to 15 minutes). If the deploy fails, copy the last ~40 lines of the
   log (they contain no secrets) and STOP.
9. Verify on the service's public URL (shown at the top of the service page, ends in .onrender.com):
   a. Open <URL>/up — expect a green page (HTTP 200).
   b. Open <URL>/ — expect the Cordially home page.
   c. Sign up at <URL>/registration/new with synthetic details: name "Test Host",
      email test-host@example.com, and a password you make up (don't report it).
      Expect to land on a page saying "What can I take off your plate?".
   d. In the message box type: Plan something new   — press Enter.
      Expect a reply containing "What are we celebrating?" within about 30 seconds.
   e. In the Render service → Environment, reveal OUTBOX_PASSWORD (read it, do not report it).
      Open <URL>/dev/outbox — the browser asks for a login: username outbox, password = that value.
      Expect the outbox page to open.

CONSTRAINTS
- Do not change plan, region, disk, instance count, branch, or any environment variable.
- Do not add a custom domain, do not delete or suspend anything, do not click "Manual Deploy" more
  than once, do not enter payment details, do not send any message to anyone.
- Synthetic data only (the test sign-up above). Never paste passwords, API keys or OUTBOX_PASSWORD
  into the chat or the report.
- Do not remove ENABLE_OUTBOX (that turns real sending on — Kevin will do it later).

ACCEPTANCE GATE (all must be true; report each one)
G1 Service "cordially" shows Live.
G2 <URL>/up returns the green page.
G3 Sign-up lands on "What can I take off your plate?".
G4 "Plan something new" gets the reply "What are we celebrating?".
G5 <URL>/dev/outbox asks for a login and opens with OUTBOX_PASSWORD.
A failed gate is reported as FAILED with what you saw — never as passed.

REPORT (≤ 15 lines)
STATUS: PASS | PARTIAL | BLOCKED
URL: <service URL>
Plan / monthly cost shown: <…>   Disk: <name, size, mount path>
Deploy time: <minutes>
G1–G5: PASS/FAILED each, one line each with what you saw
Errors: exact text (deploy log tail if it failed)
BLOCKED: anything Kevin must do (sign-in, payment method, GitHub permission, cost approval)
```
