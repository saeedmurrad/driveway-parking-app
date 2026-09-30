# ParkSpace — Driveway Parking Marketplace (POC)

Two-sided marketplace: hosts rent out driveways, drivers find, book and prepay. Platform keeps 20%.
Full requirements: *Driveway Parking App – Developer Specification*.

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

```bash
# backend
cd backend && cp .env.example .env   # fill DATABASE_URL
npm install && npm run start:dev

# app (web)
cd mobile && flutter run -d chrome --dart-define=API_URL=http://localhost:3000
```

## Status

Done: schema, nearby search (PostGIS), price calculator (+tests), booking creation with
double-booking protection, parked/end transitions, Flutter search screen, CI + deploy pipelines.

Next: auth (Supabase JWT), Stripe PaymentIntent + webhook, map view, host listing flow,
auto-end scheduler (`pg_cron`/cron endpoint), cancellations/refunds, admin panel.
