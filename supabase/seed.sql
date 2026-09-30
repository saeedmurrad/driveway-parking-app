-- Demo data. All demo accounts use the password: demo1234
insert into users (id, name, email, password_hash, is_driver, is_host, is_admin, verification_status) values
  ('00000000-0000-4000-8000-000000000001','Helen Hart','host@demo.parkspace.test', crypt('demo1234', gen_salt('bf')), true, true, false, 'verified'),
  ('00000000-0000-4000-8000-000000000002','Dan Driver','driver@demo.parkspace.test', crypt('demo1234', gen_salt('bf')), true, false, false, 'verified'),
  ('00000000-0000-4000-8000-000000000003','Ada Admin','admin@demo.parkspace.test', crypt('demo1234', gen_salt('bf')), true, false, true, 'verified'),
  ('00000000-0000-4000-8000-000000000004','Omar Khan','omar@demo.parkspace.test', crypt('demo1234', gen_salt('bf')), true, true, false, 'verified');

insert into vehicles (user_id, plate, make, model, colour, size) values
  ('00000000-0000-4000-8000-000000000002','AB12 CDE','Ford','Focus','Blue','medium');

insert into listings (id, host_id, title, address, postcode, latitude, longitude, space_type, max_vehicle_size,
                      features, access_instructions, price_hour, price_day, cancellation_policy, rating, status) values
 ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','Driveway near King''s Cross','12 Argyle Square, London','WC1H 8AS',51.5308,-0.1238,'driveway','large','{covered,lit,level_access}','Left side of the drive. Don''t block the garage door.',2.50,14.00,'flexible',4.8,'live'),
 ('10000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000001','Private garage by Euston','5 Euston Street, London','NW1 2EA',51.5282,-0.1337,'garage','medium','{covered,cctv,gated,lit}','Gate code 4471#. Garage is the green door.',3.00,18.00,'moderate',4.9,'live'),
 ('10000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000001','Bloomsbury gated bay','22 Bedford Place, London','WC1B 5JH',51.5246,-0.1256,'bay','small','{gated,cctv}','Buzz flat 2 on arrival.',3.50,22.00,'strict',4.6,'live'),
 ('10000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-000000000001','Camden driveway with EV charger','48 Camden Road, London','NW1 9DP',51.5390,-0.1426,'driveway','large','{ev_charging,lit,level_access}','Type 2 cable in the green box by the gate.',3.20,19.00,'flexible',4.7,'live'),
 ('10000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000001','Islington courtyard space','9 Upper Street, London','N1 0PQ',51.5362,-0.1030,'forecourt','van','{gated,lit,cctv}','Enter through the arch, space 3.',2.80,16.00,'moderate',4.5,'live'),
 ('10000000-0000-4000-8000-000000000006','00000000-0000-4000-8000-000000000004','Shoreditch driveway','31 Bethnal Green Rd, London','E1 6GY',51.5254,-0.0786,'driveway','medium','{lit}','Drive on the right-hand side of the house.',2.20,12.00,'flexible',4.4,'live'),
 ('10000000-0000-4000-8000-000000000007','00000000-0000-4000-8000-000000000004','Waterloo covered parking bay','14 The Cut, London','SE1 8LN',51.5031,-0.1132,'bay','medium','{covered,cctv,gated}','Fob at the gate is on the key hook by the door.',4.00,26.00,'moderate',4.9,'live'),
 ('10000000-0000-4000-8000-000000000008','00000000-0000-4000-8000-000000000004','Canary Wharf forecourt','3 Marsh Wall, London','E14 9SH',51.5054,-0.0235,'forecourt','large','{gated,lit,level_access}','Ring bell 6.',3.80,24.00,'flexible',null,'pending_approval');

-- Feature flags for demos: price negotiation, request-to-book, and office-hours availability.
update listings set allow_offers = true, min_offer_price = 1.75 where id = '10000000-0000-4000-8000-000000000001';
update listings set allow_offers = true, min_offer_price = 2.20 where id = '10000000-0000-4000-8000-000000000002';
update listings set allow_offers = true, min_offer_price = 1.50 where id = '10000000-0000-4000-8000-000000000006';
update listings set booking_mode = 'request' where id = '10000000-0000-4000-8000-000000000007';
-- Bloomsbury bay is only available Mon-Fri 07:00-19:00 (UK time).
insert into availability_rules (listing_id, day_of_week, start_time, end_time)
  select '10000000-0000-4000-8000-000000000003', d, '07:00', '19:00' from generate_series(1, 5) d;

-- Booking history so dashboards look alive: completed past bookings (driver Dan).
do $$
declare
  i int; l uuid; h uuid; s timestamptz; e timestamptz; hrs int; price numeric; comm numeric; bid uuid;
  v uuid := (select id from vehicles limit 1);
  ls uuid[] := array['10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000006','10000000-0000-4000-8000-000000000007','10000000-0000-4000-8000-000000000004']::uuid[];
begin
  for i in 1..5 loop
    l := ls[i];
    select host_id into h from listings where id = l;
    hrs := 2 + i;
    s := date_trunc('hour', now()) - (i * interval '3 days');
    e := s + hrs * interval '1 hour';
    select price_hour * hrs into price from listings where id = l;
    comm := round(price * 0.20, 2);
    bid := gen_random_uuid();
    insert into bookings (id, reference, listing_id, driver_id, host_id, vehicle_id, booked_start, booked_end, blocked_end,
        actual_parked_at, actual_ended_at, parking_amount, total_amount, commission_rate, commission_amount, host_earnings, status)
      values (bid, 'PS-SEED' || i, l, '00000000-0000-4000-8000-000000000002', h, v, s, e, e + interval '15 minutes',
        s + interval '4 minutes', e - interval '6 minutes', price, price, 0.2, comm, price - comm, 'completed');
    insert into booking_events (booking_id, event, actor, created_at) values
      (bid,'created','driver', s - interval '1 day'), (bid,'paid','driver', s - interval '1 day'),
      (bid,'parked','driver', s + interval '4 minutes'), (bid,'ended','driver', e - interval '6 minutes');
    insert into transactions (booking_id, user_id, type, amount, created_at) values
      (bid,'00000000-0000-4000-8000-000000000002','charge', price, s - interval '1 day'),
      (bid,null,'commission', comm, e), (bid,h,'host_earning', price - comm, e);
  end loop;
end $$;
