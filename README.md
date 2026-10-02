# ParkSpace — Driveway Parking Marketplace (POC)

Two-sided marketplace: hosts rent out driveways, drivers find, book and prepay. Platform keeps 20%.
Full requirements: [Developer Specification (PDF)](docs/Driveway-Parking-App-Developer-Specification.pdf).

## Live demo

- **App:** https://saeedmurrad.github.io/driveway-parking-app/ (use the Driver / Host / Admin demo buttons)
- **API health:** https://parkspace-api.onrender.com/health (the free tier sleeps when idle, so the first load can take about a minute)

## Architecture (all free tier)

| Layer | Tech | Hosted on |
|---|---|---|
| Mobile + web app | Flutter (`mobile/`) | GitHub Pages (web), APK via CI later |
| API | NestJS (`backend/`) | Render (free web service) |
| Database | Postgres + PostGIS (`supabase/`) | Supabase (free) |
| Payments | Stripe Connect, test mode | Stripe |

Key design points: the **`no_double_booking` exclusion constraint** in `supabase/migrations/0001_init.sql`
prevents overlapping bookings at database level; the money ledger (`transactions`) and
`booking_events` are append-only, so totals are always `SUM`s; commission % lives in the
`settings` table and is stored per booking.

## Deploy (all free tiers)

1. **Supabase** (database): sign in with GitHub, create a project (region: London), then *Connect* > **Session pooler** URI.
   Save it as `DATABASE_URL=...` in a git-ignored file called `.deploy.env`, then run `scripts/apply_db.sh`
   (empty database only; it loads the schema and demo data using Docker).
2. **Render** (API): sign in with GitHub, *New > Blueprint*, pick this repo, and paste the same value as the
   `DATABASE_URL` secret. Note the service URL, e.g. `https://parkspace-api.onrender.com`.
3. **GitHub Pages** (web app): Settings > Pages > Source = *GitHub Actions*; Settings > Secrets and variables >
   Actions > Variables > add `API_URL` = the Render URL; re-run *Deploy Flutter Web*.
4. Site: `https://saeedmurrad.github.io/driveway-parking-app/`

> Render's free tier sleeps when idle: open `<API_URL>/health` a minute before a demo.
> Uploaded photos live on the API's disk and are lost on redeploy (the demo photos are re-created automatically).
> `DEMO_MODE=true` shows verification codes in the app because email/SMS are not wired up yet.

## Run locally

**Easiest: Docker** (Postgres+PostGIS with schema and seed auto-loaded, plus the API on :3000):

```bash
colima start            # or start Docker Desktop
docker compose up --build
curl localhost:3000/health
docker compose down -v  # stop and wipe the DB (schema + seed reload next start)
```

**Without Docker:**

```bash
# backend
cd backend && cp .env.example .env   # fill DATABASE_URL
npm install && npm run start:dev

# app (web)
cd mobile && flutter run -d chrome --dart-define=API_URL=http://localhost:3000
```

## Demo accounts (password `demo1234`)

| Role | Email |
|---|---|
| Driver | `driver@demo.parkspace.test` |
| Host | `host@demo.parkspace.test` (also `omar@demo.parkspace.test`) |
| Admin | `admin@demo.parkspace.test` |

The login screen has one-tap buttons for Driver, Host and Admin.

## What works

Everything in the spec's Phase 1 **and Phase 2**, verified by `scripts/e2e.py` (196 checks) plus 22 backend unit tests.

- **Accounts:** register with Terms/Privacy acceptance (version + time stored), email + SMS code verification
  (required before booking or listing), forgot/reset password, suspend/reinstate, block users,
  UK GDPR data export and account deletion (financial records kept, the rest anonymised).
- **Driver:** map search (OpenStreetMap) with price pins, thumbnails, walking time, filters (price, instant book,
  covered, CCTV, EV, gated), sorting, place search; space page with photo gallery and live price breakdown;
  paid extras (CCTV, EV charging with connector matching, car wash); instant book, **request-to-book**
  (card held, charged only on host acceptance); **price negotiation** (offer, counter up to 3 rounds, expiry,
  15-minute pay window, contact-info blocking, closes when the slot is booked); I've Parked with GPS check
  (warns over ~200 m) and optional photo; End Booking; **extend** a stay; cancel with policy refunds
  (commission refunded in proportion); overstay fees; in-app chat; report a problem, including the
  "space occupied" instant refund; receipts; CSV spending statement; rebook in one tap; ratings.
- **Host:** dashboard with pending / available / frozen / paid-out earnings, listings with photo upload,
  edit, pause/resume, weekly availability + blocked dates, pricing (hourly + day rate), min/max stay, buffer,
  booking mode, offers and lowest acceptable price, extras pricing; accept/decline requests, answer
  "is the car still there?", payouts, monthly CSV statements, driver ratings on requests and offers.
- **Admin:** stats, listing approval queue (host verification, right-to-let declaration), bookings
  (refund, force-end), disputes (evidence, chat log, refund / extra-only refund, warn / suspend), users,
  settings (commission %, grace, dispute window, overstay, response times), extras catalogue, editable
  Terms / Privacy / FAQs, push announcements, audit log of every admin action.
- **Platform:** 20% commission stored per booking, append-only money ledger (every total is a SUM), database-level
  no-double-booking, weekly availability evaluated in UK time, scheduler (auto-end, no-show, request and offer
  expiry, overstay prompts, reminders), notifications in-app with push/email/SMS channels logged.

## Still simulated or not built

- **Payments are simulated** (`BookingsService.pay`); Stripe Connect test mode is the next step.
- **Email, SMS and push are not delivered.** They are stored in-app and logged. In `DEMO_MODE=true` the API also
  returns verification codes so the app can show them.
- **Not built:** Google / Apple sign-in, ID-document/selfie verification (admin "Verify" toggle instead),
  weekly/monthly prices, multi-space listings, favourites, promo codes, referrals, live CCTV link,
  smart pricing, business accounts (spec Phase 3), Apple Pay / Google Pay sheets.
- **Hosting caveats:** uploaded photos live on the API's disk (use a persistent volume, or R2 / Supabase Storage);
  the scheduler runs inside the API process; OpenStreetMap tiles and Nominatim are fair-use only;
  the dispute window is 2 minutes for demos (spec default is 24 hours, editable in Admin).
- Android and iOS builds compile but have only been exercised on web.

## Tests

```bash
docker compose up -d --build
python3 scripts/e2e.py                 # 196 API acceptance checks (resets its own test data)
cd backend && npx jest                 # unit tests
cd mobile && flutter analyze && flutter test
```
