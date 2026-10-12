# Larkspur — digital invitations, RSVPs & guest lists

Larkspur is an original web app for designing and sending digital invitations and managing event
guests: hosts create an event, design an invitation, invite guests by email or a shareable link, and
track RSVPs; guests open a mobile-friendly invitation and reply without creating an account.

All names, visual design, templates, SVG artwork and code in this repository were created for this
project. Fonts are open-source (SIL OFL) and self-hosted; their licenses are in `vendor/font-licenses/`.

> This repository started life as the *Ruby on Rails Tutorial* sample app (Rails 3.0). That app
> can't run on a modern Ruby, so it was moved — history intact — to `legacy/rails3_sample_app/`,
> and Larkspur was built on the same stack, upgraded: **Rails 8.1, Ruby 3.3, SQLite, RSpec**.
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
| `demo@larkspur.test` | `larkspur-demo-1` |

…or create your own account at **Get started**.

**Where do emails go?** In development nothing leaves your machine. Every email and SMS lands in the
**dev outbox** at http://localhost:3000/dev/outbox (also linked in the footer). Open an invitation
there and click the personal link to experience the guest side.

### Try the end-to-end flow (≈2 minutes)

1. **Create an event** — *New event*: title, date/time (entered in the event's time zone), location
   or video link, RSVP deadline, capacity, plus-ones.
2. **Add a guest** — *Add guest* with your own name and any email address.
3. **Publish** — the *Publish* button on the event page (drafts can't be opened by guests).
4. **Send invitations** — *Send N invitations*. Click it twice: the second send is a no-op.
5. **Open the invitation as the guest** — go to `/dev/outbox`, open the email, click the personal link.
   Use a private window if you want the view to count as a guest open.
6. **RSVP** — choose yes/maybe/no, party size, answer questions, leave a note. Reopen the same link
   later to change the response.
7. **See the response** — back on the event dashboard: stats, the guest's RSVP, answers, activity.

### Running the tests

The browser specs in `spec/system/` drive headless Chrome through Cuprite. They find Chromium at
the usual paths or `BROWSER_PATH`, and are skipped (not failed) when no browser is installed.


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

The app is being built in stages; each stage is usable on its own.

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
- **Design editor** (*Design* on the event page; also step 2 after creating an event): template,
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

### ⏳ Stage 3 — bulk guest tools
CSV import with a validation summary, CSV export, bulk select actions (group, invite, remove).

### ⏳ Stage 4 — messaging
Updates and reminders to selected groups/RSVP statuses, scheduled sends, SMS via the adapter.

### ⏳ Stage 5 — co-hosts & check-in
Co-host invitations with roles (owner / editor / check-in staff) and a door check-in screen.

### ⏳ Stage 6 — optional payments
Ticketed or paid RSVPs through a payment adapter (local fake checkout + Stripe Checkout).

---

## Architecture

| Area | Where |
|------|-------|
| Events & lifecycle (draft → published → cancelled, duplicate, time-zone-aware times) | `app/models/event.rb` |
| Guests, normalization, personal links | `app/models/guest.rb`, `app/models/guest_access_token.rb` |
| RSVP rules (deadline, capacity, party size, questions) | `app/models/rsvp_submission.rb` |
| Messages, audiences, idempotent dispatch | `app/models/message.rb`, `app/models/audience.rb` |
| Per-recipient delivery state machine | `app/models/delivery.rb`, `app/jobs/delivery_job.rb` |
| Channel adapters (email, SMS) | `app/services/messaging*.rb`, `app/services/messaging/` |
| Invitation templates & design validation | `app/models/invitation_template.rb`, `app/models/invitation_design.rb` |
| Template artwork (SVG partials) and the card | `app/views/invitation_artworks/`, `app/views/invitations/_card.html.erb` |
| Design editor (server + live preview) | `app/controllers/event_designs_controller.rb`, `app/javascript/controllers/design_editor_controller.js` |
| Public share link and open RSVP | `app/controllers/public_events_controller.rb`, `app/models/link_rsvp.rb` |
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
- Guest pages send `Cache-Control: no-store`, `X-Robots-Tag: noindex` and `Referrer-Policy: no-referrer`
  (so tokens don't leak to video-call or map sites); tokens are scrubbed from request logs, and guest
  emails, phones and notes are filtered from parameter logs.
- **Access control**: every host route loads events through `current_user.accessible_events` (other
  people's events are a 404) and checks a permission from `EventPolicy`.
- **Strict Content-Security-Policy**: scripts and styles only from our origin or with a nonce; no
  inline `style` attributes. Invitation colors and fonts are emitted as CSS variables only after
  validation (hex colors, fonts from a fixed list), so design input can't inject CSS.
- **Rate limits** (Rails `rate_limit`) on sign-in, sign-up, password reset, RSVP submission, guest pages
  and invitation sends.
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
| `ENABLE_OUTBOX=1`, `OUTBOX_PASSWORD` | Demo/staging: capture all mail/SMS at `/dev/outbox` behind basic auth |
| `SECRET_KEY_BASE` | Rails secret (also signs guest links — rotating it invalidates all personal links) |

### SMS integration (designed, off by default)

SMS is a channel adapter with the same interface as email (`deliver(delivery) → Receipt`):

- `Messaging::Sms::OutboxAdapter` — development default; texts appear in `/dev/outbox`.
- `Messaging::Sms::TwilioAdapter` — Twilio Messages API over HTTPS; enable with `SMS_PROVIDER=twilio`
  and `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM_NUMBER` (or `TWILIO_MESSAGING_SERVICE_SID`).
  Numbers must be E.164 (`+15551234567`). Without credentials, SMS stays disabled in production and
  the UI won't offer it.

### Deploying

The generated `Dockerfile` builds a production image (Puma + Thruster). Mount a volume at
`/rails/storage` so the SQLite databases and uploads persist, set the variables above, and run Solid
Queue either in Puma (`SOLID_QUEUE_IN_PUMA=1`) or as a separate `bin/jobs` process.
