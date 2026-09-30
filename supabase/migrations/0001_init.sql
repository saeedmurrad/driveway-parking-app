-- ParkSpace core schema (spec section 14). Run in Supabase SQL editor or `supabase db push`.
create extension if not exists postgis;
create extension if not exists btree_gist;
create extension if not exists pgcrypto;

create table settings (
  key text primary key,
  value text not null
);
-- dispute_window_minutes: spec default is 1440 (24h); 2 min here so payouts are demoable.
insert into settings (key, value) values
  ('commission_rate', '0.20'),
  ('buffer_minutes', '15'),
  ('grace_minutes', '15'),
  ('dispute_window_minutes', '2'),
  ('overstay_multiplier', '1.5'),
  ('min_payout_gbp', '10'),
  ('overstay_response_minutes', '60'),
  ('request_response_minutes', '30');

create table users (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  email text unique not null,
  phone text,
  password_hash text,
  photo_url text,
  is_driver boolean not null default true,
  is_host boolean not null default false,
  is_admin boolean not null default false,
  verification_status text not null default 'pending',
  account_status text not null default 'active',
  rating_as_driver numeric(3,2),
  rating_as_host numeric(3,2),
  created_at timestamptz not null default now()
);

create table vehicles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id),
  plate text not null,
  make text, model text, colour text,
  size text not null default 'medium' check (size in ('small','medium','large','van')),
  is_ev boolean not null default false,
  ev_connector text
);

create table host_payout_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id),
  provider_account_id text,
  payouts_enabled boolean not null default false,
  bank_last4 text
);

create table listings (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references users(id),
  title text not null,
  address text not null,
  postcode text,
  latitude double precision not null,
  longitude double precision not null,
  location geography(Point,4326) generated always as
    (st_setsrid(st_makepoint(longitude, latitude), 4326)::geography) stored,
  space_type text not null default 'driveway',
  spaces_count int not null default 1,
  max_vehicle_size text not null default 'medium',
  features text[] not null default '{}',
  access_instructions text,
  price_hour numeric(8,2) not null,
  price_day numeric(8,2),
  price_week numeric(8,2),
  price_month numeric(8,2),
  min_stay_minutes int not null default 30,
  max_stay_minutes int not null default 43200,
  booking_mode text not null default 'instant' check (booking_mode in ('instant','request')),
  allow_offers boolean not null default false,
  min_offer_price numeric(8,2),
  cancellation_policy text not null default 'flexible' check (cancellation_policy in ('flexible','moderate','strict')),
  buffer_minutes int not null default 15,
  status text not null default 'pending_approval'
    check (status in ('draft','pending_approval','live','paused','rejected','removed')),
  rating numeric(3,2),
  created_at timestamptz not null default now()
);
create index listings_location_idx on listings using gist (location);

create table listing_photos (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references listings(id),
  url text not null,
  sort_order int not null default 0
);

create table availability_rules (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references listings(id),
  day_of_week int not null check (day_of_week between 0 and 6), -- 0 = Sunday
  start_time time not null,
  end_time time not null
);

create table availability_blocks (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references listings(id),
  start_datetime timestamptz not null,
  end_datetime timestamptz not null,
  reason text
);

create table extra_types (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  allowed_price_units text[] not null default '{per_booking}',
  active boolean not null default true
);
insert into extra_types (name, allowed_price_units) values
  ('CCTV surveillance', '{per_booking,per_day}'),
  ('EV charging', '{per_booking,per_hour,per_kwh}'),
  ('Car wash / valet', '{per_booking}');

create table listing_extras (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references listings(id),
  extra_type_id uuid not null references extra_types(id),
  price numeric(8,2) not null,
  price_unit text not null,
  details jsonb,
  active boolean not null default true
);

create table offers (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references listings(id),
  driver_id uuid not null references users(id),
  vehicle_id uuid references vehicles(id),
  start_at timestamptz not null,
  end_at timestamptz not null,
  extras jsonb,
  amount numeric(8,2) not null,
  round int not null default 1 check (round <= 4),
  sent_by text not null check (sent_by in ('driver','host')),
  parent_offer_id uuid references offers(id),
  status text not null default 'open'
    check (status in ('open','accepted','declined','countered','expired','paid')),
  expires_at timestamptz not null,
  thread_id uuid not null,            -- first offer's id; groups a negotiation
  message text,
  pay_by timestamptz,                 -- set on accept: driver has 15 minutes to pay
  decline_reason text,
  created_at timestamp with time zone not null default now()
);
create index offers_thread_idx on offers (thread_id, round);

create table bookings (
  id uuid primary key default gen_random_uuid(),
  reference text unique not null,
  listing_id uuid not null references listings(id),
  driver_id uuid not null references users(id),
  host_id uuid not null references users(id),
  vehicle_id uuid references vehicles(id),
  offer_id uuid references offers(id),
  booked_start timestamptz not null,
  booked_end timestamptz not null,
  blocked_end timestamptz not null,            -- booked_end + buffer
  actual_parked_at timestamptz,
  actual_ended_at timestamptz,
  parking_amount numeric(8,2) not null,
  extras_amount numeric(8,2) not null default 0,
  total_amount numeric(8,2) not null,
  commission_rate numeric(5,4) not null,       -- rate in force when booked
  commission_amount numeric(8,2) not null,
  host_earnings numeric(8,2) not null,
  overstay_fee numeric(8,2) not null default 0,
  status text not null default 'pending_payment'
    check (status in ('pending_payment','requested','confirmed','parked','overstay','completed','cancelled')),
  cancelled_by text,
  cancel_reason text,
  stripe_payment_intent text,
  respond_by timestamptz,                      -- request-to-book: host must answer before this
  overstay_check text check (overstay_check in ('asked','gone','still_there')),
  overstay_asked_at timestamptz,
  created_at timestamptz not null default now(),
  check (booked_end > booked_start),
  -- NO DOUBLE BOOKING: enforced by the database, not application code.
  constraint no_double_booking exclude using gist (
    listing_id with =,
    tstzrange(booked_start, blocked_end) with &&
  ) where (status in ('pending_payment','requested','confirmed','parked','overstay'))
);

create table booking_extras (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings(id),
  extra_type_id uuid not null references extra_types(id),
  price numeric(8,2) not null,
  price_unit text not null,
  quantity numeric(8,2) not null default 1,
  line_total numeric(8,2) not null
);

-- Append-only timeline of every status change.
create table booking_events (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings(id),
  event text not null,
  actor text not null check (actor in ('driver','host','system','admin')),
  actor_id uuid,
  latitude double precision,
  longitude double precision,
  created_at timestamptz not null default now()
);

-- Append-only money ledger. Totals are SUMs over this table: no balance column.
create table transactions (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid references bookings(id),
  user_id uuid references users(id),
  type text not null check (type in ('charge','refund','commission','host_earning','payout','overstay_fee')),
  amount numeric(8,2) not null,
  currency text not null default 'GBP',
  provider_ref text,
  status text not null default 'succeeded',
  created_at timestamptz not null default now()
);

create table payouts (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references users(id),
  amount numeric(8,2) not null,
  provider_ref text,
  status text not null default 'pending',
  sent_at timestamptz
);

create table reviews (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings(id),
  from_user_id uuid not null references users(id),
  to_user_id uuid not null references users(id),
  listing_id uuid references listings(id),
  stars int not null check (stars between 1 and 5),
  comment text,
  created_at timestamptz not null default now()
);

create table disputes (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings(id),
  opened_by uuid not null references users(id),
  type text not null,
  description text,
  photos text[],
  status text not null default 'open' check (status in ('open','in_review','resolved')),
  resolution text,
  refund_amount numeric(8,2),
  admin_id uuid,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create table messages (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings(id),
  sender_id uuid not null references users(id),
  text text not null,
  created_at timestamptz not null default now()
);

create table notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id),
  type text not null,
  title text not null,
  body text,
  read boolean not null default false,
  ref_type text,   -- 'booking' | 'offer' | 'dispute'
  ref_id uuid,
  channels text[] not null default '{push}',
  created_at timestamptz not null default now()
);
create index notifications_user_idx on notifications (user_id, created_at desc);

create table admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null,
  action text not null,
  target text,
  details jsonb,
  created_at timestamptz not null default now()
);

-- Is a listing open for the whole window? Weekly rules are evaluated in UK local time
-- (samples every 30 minutes); one-off host blocks always win. No rules = open 24/7.
create or replace function listing_available(p_listing uuid, p_start timestamptz, p_end timestamptz)
returns boolean language sql stable as $$
  select
    not exists (
      select 1 from availability_blocks ab
      where ab.listing_id = p_listing and tstzrange(ab.start_datetime, ab.end_datetime) && tstzrange(p_start, p_end))
    and (
      not exists (select 1 from availability_rules r where r.listing_id = p_listing)
      or not exists (
        select 1 from generate_series(p_start, p_end - interval '1 minute', interval '30 minutes') g(t)
        where not exists (
          select 1 from availability_rules r
          where r.listing_id = p_listing
            and r.day_of_week = extract(dow from (g.t at time zone 'Europe/London'))::int
            and r.start_time <= (g.t at time zone 'Europe/London')::time
            and r.end_time > (g.t at time zone 'Europe/London')::time)));
$$;

-- Nearby search: live listings within radius that are free for the whole window
-- (incl. buffer), fit the vehicle, respect min/max stay and availability.
create or replace function search_listings(
  p_lat double precision, p_lng double precision, p_radius_m int,
  p_start timestamptz, p_end timestamptz, p_vehicle_size text default 'medium'
) returns table (
  id uuid, title text, latitude double precision, longitude double precision,
  price_hour numeric, price_day numeric, distance_m double precision, rating numeric,
  features text[], space_type text, max_vehicle_size text, booking_mode text,
  cancellation_policy text, host_name text, allow_offers boolean
) language sql stable as $$
  select l.id, l.title, l.latitude, l.longitude, l.price_hour, l.price_day,
         st_distance(l.location, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography) as distance_m,
         l.rating, l.features, l.space_type, l.max_vehicle_size, l.booking_mode,
         l.cancellation_policy, split_part(u.name, ' ', 1) as host_name, l.allow_offers
  from listings l
  join users u on u.id = l.host_id
  where l.status = 'live'
    and st_dwithin(l.location, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, p_radius_m)
    and array_position(array['small','medium','large','van'], p_vehicle_size)
        <= array_position(array['small','medium','large','van'], l.max_vehicle_size)
    and extract(epoch from (p_end - p_start)) / 60 between l.min_stay_minutes and l.max_stay_minutes
    and not exists (
      select 1 from bookings b
      where b.listing_id = l.id
        and b.status in ('pending_payment','requested','confirmed','parked','overstay')
        and tstzrange(b.booked_start, b.blocked_end) && tstzrange(p_start, p_end + make_interval(mins => l.buffer_minutes))
    )
    and listing_available(l.id, p_start, p_end)
  order by distance_m;
$$;
