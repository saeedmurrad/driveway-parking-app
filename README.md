# ParkSpace — Driveway Parking Marketplace (POC)

Two-sided marketplace: hosts rent out driveways, drivers find, book and prepay. Platform keeps 20%.
Full requirements: [Developer Specification (PDF)](docs/Driveway-Parking-App-Developer-Specification.pdf).

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

## One-time setup

1. **Supabase**: create a project, open *SQL editor*, run `supabase/migrations/0001_init.sql`, then `supabase/seed.sql`.
   Copy the pooled connection string (Project Settings > Database).
2. **Render**: New > Blueprint > select this repo. Set `DATABASE_URL` (and Stripe keys when ready).
   Note the service URL, e.g. `https://parkspace-api.onrender.com`.
3. **GitHub**: Settings > Pages > Source = *GitHub Actions*. Settings > Secrets and variables > Actions > Variables:
   add `API_URL` = your Render URL. Push to `main` (or run the *Deploy Flutter Web* workflow).
4. Site: `https://saeedmurrad.github.io/driveway-parking-app/`

> Render's free tier sleeps when idle: open `<API_URL>/health` a minute before a demo.

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

## What works (Phase 1 of the spec)

- **Driver:** map search (OpenStreetMap) with price pins, filters and sorting, place search,
  start time and duration, space details with price breakdown, simulated card checkout,
  address revealed only after payment, I've Parked / End Booking with timestamps,
  cancel with policy-based refund, ratings, bookings tabs, spending summary, vehicles.
- **Host:** dashboard with earnings (pending / available / paid out), my spaces with pause/resume,
  add-a-space form with map pin (goes to admin approval), earnings page with payouts, cancel bookings.
- **Admin:** overview stats, listing approval queue, all bookings, editable settings
  (commission %, grace period, dispute window, payout minimum).
- **Platform:** 20% commission stored per booking, append-only ledger (totals are SUMs),
  database-level no-double-booking, auto-end and unpaid-booking expiry via a scheduler.

## Not built yet

Stripe (payment is simulated behind `BookingsService.pay`), phone/SMS verification, push
notifications, negotiation, extras, in-app chat, disputes, overstay fees, request-to-book,
availability calendar UI, photo upload.
