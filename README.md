# Cordially — digital invitations, RSVPs & guest lists

Cordially is an original web app for designing and sending digital invitations and managing event
guests: hosts create an event, design an invitation, invite guests by email or a shareable link, and
track RSVPs; guests open a mobile-friendly invitation and reply without creating an account.

All names, visual design, templates, SVG artwork and code in this repository were created for this
project. Fonts are open-source (SIL OFL) and self-hosted; their licenses are in `vendor/font-licenses/`.

> This repository started life as the *Ruby on Rails Tutorial* sample app (Rails 3.0). That app
> can't run on a modern Ruby, so it was moved — history intact — to `legacy/rails3_sample_app/`,
> and Cordially was built on the same stack, upgraded: **Rails 8.1, Ruby 3.3, SQLite, RSpec**.
> The original `PagesController` (home/about/contact) lives on in the new app.

---

## Quick start

Requirements: Ruby 3.3 (see `.ruby-version`), Bundler, SQLite 3. No Node.js, Redis or external
services are needed — JavaScript uses import maps, jobs/cache run on SQLite, and email/SMS go to a
local outbox in development.

```bash
bundle install
bin/rails db:prepare        # creates the database and loads demo data (db/seeds.rb)
bin/dev                     # or: bin/rails server
```

Open http://localhost:3000 and sign in with the demo host:

| Email                | Password          |
|----------------------|-------------------|
| `demo@cordially.test` | `cordially-demo-1` |

…or create your own account at **Get started**.

**Where do emails go?** In development nothing leaves your machine. Every email and SMS lands in the
**dev outbox** at http://localhost:3000/dev/outbox (also linked in the footer). Open an invitation
there and click the personal link to experience the guest side.

### Try the end-to-end flow (≈2 minutes)

1. **Create an event** — *New event*: title, date/time (entered in the event's time zone), location
   or video link, RSVP deadline, capacity, plus-ones.
2. **Add a guest** — *Guests* in the event sidebar → *Add guest*, with your own name and any email address.
3. **Publish** — the *Publish* button on the event's Overview (drafts can't be opened by guests).
4. **Send invitations** — *Send N invitations* on the Overview. Click it twice: the second send is a no-op.
5. **Open the invitation as the guest** — go to `/dev/outbox`, open the email, click the personal link.
   Use a private window if you want the view to count as a guest open.
6. **RSVP** — choose yes/maybe/no, party size, answer questions, leave a note. Reopen the same link
   later to change the response.
7. **See the response** — back on the event's Overview (replies, meal tally, activity) and *Guests*
   (the guest's reply and answers).

### More to try

Every event opens in a workspace with a sidebar: Overview, Guests, Design, Messages, RSVP form,
Check-in, Settings and Co-hosts (each person sees only the sections their role allows).

- **Design** (sidebar → *Design*): the studio — templates, words, fonts/colors/layout, photo; Desktop/Phone preview.
- **Share link** (sidebar card): copy it, or share straight to WhatsApp, Messages or the device share
  sheet. Turn on open replies in *Settings*.
- **Import** a CSV or pasted list, **export** the guest list, tick guests for **bulk actions**.
- **Messages**: *Remind non-responders*, schedule a *Day-before reminder*, open a delivery report.
- **Co-hosts**: invite a second account you create; the invitation email is in the dev outbox.
- **Check-in**: open *Check-in*, or scan the QR pass on an attending guest's invitation page.
- **Tickets**: set a price in *Settings* (the seeded "Autumn Supper Club" draft has one), RSVP yes
  as a guest and pay on the local test checkout page.

### Running the tests

The browser specs in `spec/system/` drive headless Chrome through Cuprite, with CSRF protection
switched on (Rails turns it off in tests by default). They find Chromium at the usual paths or
`BROWSER_PATH`, and are skipped (not failed) when no browser is installed.

```bash
bin/rails db:test:prepare
bundle exec rspec            # model, request, mailer, browser and end-to-end specs
bin/rubocop                  # style
bin/brakeman                 # security static analysis
bin/ci                       # all of the above, as CI runs them
```

`spec/requests/end_to_end_spec.rb` drives the full host → guest → host flow through the real HTTP
endpoints, including the double-submit idempotency check.

---

## Build stages

The app was built in six stages; each is usable on its own. All six are complete.

### ✅ Stage 1 — end-to-end core flow

What works:

- **Accounts** for hosts (sign up, sign in, password reset). Guests never need an account.
- **Events**: create, edit, duplicate (optionally with a fresh copy of the guest list), publish,
  cancel (with an optional note emailed to invited guests), delete. Title, host display name, start /
  end, IANA time zone, venue, address, video link, description, RSVP deadline, capacity, default
  plus-ones, "maybe" on/off.
- **Guests**: add/edit/remove manually with name, email, phone, group and plus-ones; private host notes;
  search and filter by RSVP status or group.
- **Invitations by email** with a personal, signed RSVP link and an `.ics` attachment; an optional
  personal note; per-guest resend. **Sending is idempotent** (see below).
- **Delivery status** per guest: not sent / sending / sent / failed / unconfirmed / opened.
- **Guest experience**: mobile-friendly invitation, RSVP yes/no/maybe, party size, custom questions,
  a note to the host; change the RSVP via the same link until the deadline; add to Apple/Outlook
  (`.ics`), Google Calendar or Outlook.com; see host updates; one-click stop-emails.
- **RSVP rules**: deadline, capacity (checked inside a transaction), party size limits, required
  questions; hosts can record or override an RSVP on a guest's behalf.
- **Custom RSVP questions**: short answer, paragraph, multiple choice; required or optional; asked of
  everyone or only attending guests; reorderable; choice tallies on the dashboard.
- **Host dashboard**: headcount, yes/maybe/no/awaiting, capacity remaining, opens, answers,
  recent activity, a guest-preview mode.

### ✅ Stage 2 — design editor & sharing

What works:

- **Ten original templates** (Garden Arch, Confetti Burst, Gilded Fan, Starlit, Citrus Picnic,
  Gallery, Watercolor Bloom, Winter Pines, Retro Sunset, Plain Paper), each with SVG artwork drawn for
  this app (`app/views/invitation_artworks/`). The artwork paints with the invitation's own colors, so
  recoloring a template recolors its art.
- **Design editor** (*Design* in the event sidebar; also step 2 after creating an event): template,
  headline / small line / card message, heading and body fonts (10 self-hosted OFL fonts), background /
  text / accent colors with palette suggestions and a live readability (contrast) warning, four layouts
  (centered, left, framed, side by side), artwork on/off.
- **Upload your own photo or artwork** (PNG/JPEG/WebP/GIF ≤ 8 MB) as a banner, a round inset, or the
  full card background — e.g. Plain Paper + full background for a fully custom design. SVG uploads are
  refused because they can carry script.
- **Live desktop and mobile previews**: every change updates instantly; the card is a CSS size
  container, so it renders identically as a thumbnail, in the phone frame and full size.
- **Shareable public link** (`/e/<token>`): the invitation without any guest data or the private
  video-call link. Optional **open RSVP**: visitors give a name and email, join the guest list, and get
  their personal link by email. An email that's already on the list is never answered for — that
  address is just sent its own link (at most once per 10 minutes). Hosts can revoke and regenerate the
  link, and choose whether guests see how many people are coming.
- **Envelope reveal** the first time a guest opens their invitation (skipped with reduced motion,
  without JavaScript, or on later visits).

### ✅ Stage 3 — bulk guest tools

What works:

- **Import** from a CSV file (Excel, Numbers, Google Sheets) or a pasted list, in two steps: a preview
  that marks every row *new*, *update*, *skip* (already listed / repeated in the file) or *fix needed*
  (with the reason), then **Import** to apply. Understands common header names ("First name" + "Last
  name", "E-mail address", "Mobile", "Side", "Plus-ones", …), headerless lists, comma / semicolon / tab
  separators, UTF-8 with or without BOM and Windows-1252. Optionally updates existing guests' details
  (never their RSVPs). Limits: 1 MB / 2,000 rows. The raw upload is erased once applied or discarded.
- **Export** the guest list as CSV: contact details, RSVP, party size, timestamps, every question's
  answer, notes, check-in. Cells a spreadsheet would run as formulas (`=`, `+`, `-`, `@`) are neutralized.
- **Bulk actions** on ticked guests: send invitations (still never double-sends), set or clear a group,
  remove. Guest IDs from other events are ignored.
- Pagination (100 per page) alongside search and status/group filters; a downloadable CSV template.
- Custom RSVP questions shipped in Stage 1 (short answer, paragraph, multiple choice; required or not;
  everyone or attending guests only; reorderable; tallies on the dashboard).

### ✅ Stage 4 — messaging, reminders & delivery status

What works:

- **Updates and reminders** (*Messages* in the event sidebar) to guests filtered by RSVP status and/or
  group, by email and/or SMS. Presets: *Remind non-responders* and a *Day-before reminder* for attending
  guests. A live count shows how many guests the message will reach; sending to nobody is refused.
  Only guests who were invited or have replied ever receive updates.
- **Scheduling**: send now or at a time in the event's time zone; cancel before it goes out. Recipients
  are resolved at send time. A scheduled job plus a once-a-minute sweep (`config/recurring.yml`) send it;
  an atomic claim guarantees it goes out once even if both fire (`bin/rails messages:dispatch_due` runs
  the sweep manually in development).
- **Delivery reports** per message: queued / sending / sent / delivered / failed / bounced /
  unconfirmed per guest and channel, error reasons, whether the guest opened their invitation since,
  and *Retry failed*.
- **SMS** for invitations and messages when a provider is configured (development uses the outbox):
  short composed texts with the personal link and "Reply STOP to opt out".
- **Provider webhooks** — `POST /webhooks/email` (bounces, deliveries, spam complaints; generic JSON or
  SendGrid's event format; bearer-token auth via `EMAIL_WEBHOOK_TOKEN`) and Twilio status + inbound
  callbacks (`/webhooks/twilio/status`, `/webhooks/twilio/inbound`, verified with `X-Twilio-Signature`;
  STOP replies stop all messages to that number). Complaints and STOPs unsubscribe the guest.
- Guests see updates and reminders on their invitation page under "Updates from the host".

### ✅ Stage 5 — co-hosts & check-in

What works:

- **Co-hosts** (*Co-hosts* in the event sidebar, owner only): invite by email as **Co-host** (edit event
  and design, manage guests, send messages, check-in) or **Door staff** (check-in only). Only the owner
  can cancel or delete the event and manage co-hosts. Co-hosts see the event in their dashboard with
  their role, and can leave. Invitation links are single-use, expire after 14 days, are stored only as
  a SHA-256 digest, and can only be accepted by a signed-in account with the invited email address
  (sign-in/sign-up returns to the invitation).
- **Permissions** are enforced server-side per action (`EventPolicy`): door staff never see contact
  details, personal RSVP links, answers or exports — they're taken straight to the door screen.
- **Check-in** (*Check-in* in the event sidebar; *Scan pass* uses the camera where the browser supports it): arrivals vs. expected headcount, search by name,
  check a whole party or part of it in, undo mistakes, optionally include guests who didn't say yes.
- **QR passes**: attending guests see a pass on their invitation page. It encodes a check-in code that
  is separate from their RSVP link (so scanning it never grants the power to change the RSVP); any
  phone camera opens the staff check-in page for that guest. Rotating a guest's link revokes the pass.

| Role | Edit event & design | Guests & contacts | Messages | Check-in | Cancel / delete | Co-hosts |
|------|:---:|:---:|:---:|:---:|:---:|:---:|
| Owner | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Co-host | ✓ | ✓ | ✓ | ✓ | – | – |
| Door staff | – | names only | – | ✓ | – | – |

### ✅ Stage 6 — optional payments

What works:

- **Ticketed events**: the owner sets a price per person and currency in *Settings* (blank = free;
  co-hosts can't change pricing). Guests who RSVP **yes** see what they owe for their party and pay
  through hosted checkout; maybes and declines owe nothing. Adding people later asks only for the
  difference.
- **Gateway adapter** (`app/services/payments/`): a local **test checkout** page in development (no
  credentials; the link is signed) and **Stripe Checkout** via its REST API when configured — per-attempt
  idempotency keys, redirects only to `https://checkout.stripe.com`, and a webhook (`/webhooks/stripe`)
  verified with `Stripe-Signature` (HMAC-SHA256, 5-minute tolerance) that records the payment once, only
  when the paid amount matches. Expired sessions are marked and can be restarted.
- **Idempotent checkout**: clicking *Pay* twice (or concurrently) reuses one pending payment and one
  checkout session (row lock); a "completed" event delivered twice records the payment once.
- The dashboard shows Paid / Part paid / Unpaid per guest and the total collected; the CSV export includes
  paid and due amounts; payments survive a guest's removal for record-keeping.

Not included (by design, for now): refunds and partial-attendance credits are handled in the Stripe
dashboard; unpaid "yes" RSVPs hold their seats until the host follows up.

---

### ✅ Stage 7 — Cordially redesign ("Midnight Letterpress")

Designed first on a Claude Design canvas (foundations, landing, overview, guests, studio, guest phone
view, door), then implemented across every screen:

- **Brand**: wax-seal mark (`app/views/shared/_brand_mark.html.erb`, `public/icon.svg|png`), night-ink
  marketing, porcelain app ground, wax-berry and gold-foil accents; Instrument Serif / Instrument Sans
  (self-hosted, OFL — licenses in `vendor/font-licenses/`).
- **Layouts**: `marketing` (landing, about, contact), `application` (app header with event crumb and
  account menu), `event` (workspace sidebar, nested in the app layout; role-aware links, share card).
- **Event workspace**: Overview (live card on its envelope, replies with meter and meal tally, getting-ready
  checklist or send panel, reminders, activity), Guests (search, segmented filter, bulk bar, monograms),
  RSVP form (questions with tallies and a guest-eye preview), Settings (details, share link, duplicate,
  danger zone), Studio (tab rail + live Desktop/Phone stage), Door (night header, camera pass scanner).
- **Sharing**: WhatsApp / Messages / native share sheet for the public link (never a personal link);
  guest pages carry a "Hosting something?" link back to Cordially.
- Icons are drawn for the app (`IconHelper`); every page still passes the strict CSP (no inline styles).

### ✅ Stage 8 — hosting essentials

- **Adults & kids** (Settings → RSVPs): guests use steppers for adults and kids; the party size is
  their sum and stays within the invitation's limit. **Plus-one names** optional per event.
  Overview, guest list and CSV export show the breakdown and names.
- **Host notifications** (account menu → *Settings*): an email per reply (default), one daily summary
  (`HostDigestJob`, hourly in production, at most one summary per 20 hours), or off. Co-hosts get
  them too; door staff don't; nobody is told about a reply they recorded themselves.
- **Automatic reminders** (Settings → Automatic reminders): nudge non-responders N days before the
  deadline, and remind everyone coming the day before, at 10am event time. They're scheduled
  Messages kept in step with the dates (`AutoReminders`); cancelling one in Messages turns it off.
- **Scheduled invitations**: *Send invitations → Later* sends to everyone still uninvited at that time.
- **Guestbook**: invited guests leave notes for the host and each other on the invitation page
  (never on the public share page); hosts hide notes from the Overview. Rate-limited per guest.

### ✅ Stage 9 — richer cards

- **Card back**: guests flip the card for the details, directions (Google Maps, Apple Maps) and a ride
  (Uber), plus the host's links — book a table (OpenTable, Resy, Tock, SevenRooms), registries (Zola,
  Amazon, Target, Babylist, Honeyfund…), a playlist, a photo album. Links are plain URLs (no partner
  API needed); well-known services are recognized and labeled (`EventLink::PROVIDERS`). Studio → *Back*.
- **Envelope**: color, liner (stripe, dots, foil, check, starry, confetti), stamp and page backdrop
  (Studio → *Envelope*). The envelope arrives sealed with the guest's name; the flap opens to show the liner.
- **Photo gallery** (Studio → *Photos*): up to 12 photos below the card.
- **Six new templates**: Festival Lights, Balloon Bunch, Seaside, Bubbles, Wildflower Meadow, Trailhead.
- **Card types** (Settings): *Invitation*, *Save the date* (no replies; send the invitation to the same
  list later) or *Announcement* (no date required).
- **Print at home** (Overview → *Print*): front and back at 5 × 7 in, or *Save as PDF* for a print shop.
- **Installable app**: web app manifest + service worker (offline page), so hosts and door staff can
  add Cordially to their home screen.

### ✅ Stage 10 — contacts

- **Address book** (*Contacts* in the header): private to each host; add, edit, search, export CSV.
- **Import** from a phone/Google/Outlook export (vCard `.vcf`) or any CSV/pasted list. Existing
  contacts (same email) only get missing details filled in.
- **Add from contacts** on any guest list (tick people), or **copy another event's list** (fresh
  links, no replies; only from events where you can see contact details).
- New guests and imported lists can be saved to contacts as you go (on by default, per form).

## Architecture

| Area | Where |
|------|-------|
| Events & lifecycle (draft → published → cancelled, duplicate, time-zone-aware times) | `app/models/event.rb` |
| Guests, normalization, personal links | `app/models/guest.rb`, `app/models/guest_access_token.rb` |
| RSVP rules (deadline, capacity, party size, questions) | `app/models/rsvp_submission.rb` |
| Messages, audiences, idempotent dispatch | `app/models/message.rb`, `app/models/audience.rb` |
| Per-recipient delivery state machine | `app/models/delivery.rb`, `app/jobs/delivery_job.rb` |
| Channel adapters (email, SMS) | `app/services/messaging*.rb`, `app/services/messaging/` |
| Compose, schedule, reports; scheduled dispatch | `app/controllers/messages_controller.rb`, `app/jobs/dispatch_*` |
| Provider webhooks | `app/controllers/webhooks/` |
| Invitation templates & design validation | `app/models/invitation_template.rb`, `app/models/invitation_design.rb` |
| Template artwork (SVG partials) and the card | `app/views/invitation_artworks/`, `app/views/invitations/_card.html.erb` |
| Design editor (server + live preview) | `app/controllers/event_designs_controller.rb`, `app/javascript/controllers/design_editor_controller.js` |
| Public share link and open RSVP | `app/controllers/public_events_controller.rb`, `app/models/link_rsvp.rb` |
| Guest import / export | `app/models/guest_import.rb`, `app/models/guest_list_export.rb`, `app/models/csv_safety.rb` |
| Payments (model, gateways, webhook) | `app/models/payment.rb`, `app/services/payments/`, `app/controllers/webhooks/stripe_controller.rb` |
| Co-hosts and invitations | `app/models/event_membership.rb`, `app/models/cohost_invitation.rb`, `app/controllers/cohost*_controller.rb` |
| Check-in and QR passes | `app/controllers/check_ins_controller.rb`, `Guest#check_in!`, `GuestAccessToken.check_in_code` |
| Calendar files and links | `app/models/calendar_invite.rb` |
| Who may do what on an event | `app/models/event_policy.rb`, `app/controllers/concerns/event_scoped.rb` |
| Guest-facing pages | `app/controllers/guest_invitations_controller.rb`, `app/views/guest_invitations/` |

Background jobs use Active Job: in-process (`:async`) in development, Solid Queue (SQLite-backed,
persistent) in production — run `bin/jobs`, or set `SOLID_QUEUE_IN_PUMA=1` to run it inside Puma.

### Idempotent sending

Retries must never produce duplicate invitations. Four layers make that hold:

1. **Form idempotency key.** Each "Send" form embeds a one-time key; `messages` has a unique index on
   `(event_id, idempotency_key)`, so a double click or a retried POST finds the existing message.
2. **Unique deliveries.** `deliveries` is unique on `(message_id, guest_id, channel)` and is filled with
   `INSERT … ON CONFLICT DO NOTHING`, so re-dispatching only adds missing recipients.
3. **Invitation de-duplication across sends.** A new invitation send skips guests who already have a
   queued/sending/sent invitation (failed ones are retried). Re-sending to someone is an explicit action.
4. **Atomic claim per delivery.** A job sends only after `UPDATE … SET status='sending' WHERE status IN
   ('queued','failed')` affects exactly one row. If a worker dies mid-send the delivery stays
   "sending" and is shown as *unconfirmed* rather than re-sent (at-most-once for guest messages).
   Each email also carries a stable `Message-ID` derived from the delivery.

### Security & guest privacy

- **Personal links** are `/i/<40-char token>`: a random 16-character key stored on the guest plus a
  24-character HMAC signature derived from `secret_key_base`. A copy of the database alone can't
  forge links; tampered tokens are rejected in constant time; rotating the key revokes a link.
- Guest pages send `Cache-Control: no-store`, `X-Robots-Tag: noindex` and `Referrer-Policy: same-origin`
  (tokens never leak to video-call, map or calendar sites; `no-referrer` would make browsers send
  `Origin: null` on form posts and break CSRF origin checks); tokens are scrubbed from request logs, and
  guest emails, phones and notes are filtered from parameter logs.
- **Separate credentials per purpose**: a guest's RSVP link, their check-in QR code, co-host invitation
  tokens (stored as digests) and the public share link are all different secrets, each revocable.
- **Access control**: every host route loads events through `current_user.accessible_events` (other
  people's events are a 404) and checks a permission from `EventPolicy`.
- **Strict Content-Security-Policy**: scripts and styles only from our origin or with a nonce (per
  visitor, stable across Turbo visits); no inline `style` attributes. Invitation colors and fonts are emitted as CSS variables only after
  validation (hex colors, fonts from a fixed list), so design input can't inject CSS.
- **Rate limits** (Rails `rate_limit`) on sign-in, sign-up, password reset, RSVP submission, open RSVPs,
  payment starts, guest pages, imports, co-host invitations, message and invitation sends, and webhooks.
- **Webhooks** are authenticated (shared bearer token, Twilio and Stripe signatures) before any data
  is read or changed.
- **Input validation** on every model (lengths, formats, http(s)-only links, time zones, capacity).
- Guests can stop emails about an event (also via RFC 8058 one-click `List-Unsubscribe`); deleting an
  event deletes its guests, answers and delivery records.

---

## Configuration

Nothing needs configuring for local development. For production, see `.env.example`:

| Variable | Purpose |
|----------|---------|
| `APP_HOST` | Public hostname used in email links |
| `MAIL_FROM` | Sender address for guest email |
| `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` | Any SMTP provider. Without them, sends fail visibly ("Email is not configured") rather than vanishing. |
| `SMS_PROVIDER=twilio` + `TWILIO_*` | Enables SMS (see below) |
| `EMAIL_WEBHOOK_TOKEN` | Shared secret (16+ chars) that enables `POST /webhooks/email` for bounce/delivery feedback |
| `PAYMENTS_PROVIDER=stripe`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` | Paid tickets via Stripe Checkout (see below). Development defaults to a local test checkout. |
| `ENABLE_OUTBOX=1`, `OUTBOX_PASSWORD` | Demo/staging: capture all mail/SMS at `/dev/outbox` behind basic auth |
| `SECRET_KEY_BASE` | Rails secret (also signs guest links — rotating it invalidates all personal links) |

### SMS integration (designed, off by default)

SMS is a channel adapter with the same interface as email (`deliver(delivery) → Receipt`):

- `Messaging::Sms::OutboxAdapter` — development default; texts appear in `/dev/outbox`.
- `Messaging::Sms::TwilioAdapter` — Twilio Messages API over HTTPS; enable with `SMS_PROVIDER=twilio`
  and `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM_NUMBER` (or `TWILIO_MESSAGING_SERVICE_SID`).
  Numbers must be E.164 (`+15551234567`). Without credentials, SMS stays disabled in production and
  the UI won't offer it. With `APP_HOST` set, each text asks Twilio for status callbacks at
  `/webhooks/twilio/status`; point your number's incoming-message webhook at `/webhooks/twilio/inbound`
  so STOP replies are recorded. Only text guests who agreed to receive texts — regulations such as
  the US TCPA apply to the host.

### Payments (Stripe)

1. Set `PAYMENTS_PROVIDER=stripe`, `STRIPE_SECRET_KEY` (a restricted key with Checkout Sessions write
   access is enough) and `STRIPE_WEBHOOK_SECRET`.
2. In the Stripe dashboard, add a webhook endpoint `https://<APP_HOST>/webhooks/stripe` for
   `checkout.session.completed`, `checkout.session.async_payment_succeeded`,
   `checkout.session.async_payment_failed` and `checkout.session.expired`.
3. The Content-Security-Policy then also allows form redirects to `https://checkout.stripe.com`.

Without a provider in production, the ticket price field is hidden and events stay free.

### Deploying

The generated `Dockerfile` builds a production image (Puma + Thruster). Mount a volume at
`/rails/storage` so the SQLite databases and uploads persist, set the variables above, and run Solid
Queue either in Puma (`SOLID_QUEUE_IN_PUMA=1`) or as a separate `bin/jobs` process.

---

## Known limitations & next steps

- **Scale**: SQLite (with Solid Queue/Cache) suits a single server. For multiple app servers, move to
  PostgreSQL — the code avoids SQLite-specific SQL, and `RsvpSubmission` already takes a row lock on
  other databases.
- **Email feedback**: bounce/delivery webhooks match on the Message-ID we set, which SendGrid and
  similar providers echo back. Providers that only report their own IDs (e.g. Postmark) need a small
  adapter.
- **SMS**: only Twilio is implemented; numbers must be stored in E.164 form. Consent is the host's
  responsibility.
- **Accessibility & i18n**: pages use semantic HTML, labels, focus styles and reduced-motion handling,
  but haven't had a formal audit; all copy is English.
- **Not built**: guest-to-guest features (public guest lists, comments), seating charts, refunds,
  recurring events, and a native app.
- Rate limits use Rails' built-in limiter backed by the cache store (Solid Cache in production);
  put the app behind a proxy/CDN with its own limits for high-traffic events.
