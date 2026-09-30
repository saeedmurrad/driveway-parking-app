-- Demo data: a host, a driver, two live listings in central London.
insert into users (id, name, email, is_host, verification_status) values
  ('00000000-0000-0000-0000-000000000001','Helen Host','host@demo.parkspace.test', true, 'verified'),
  ('00000000-0000-0000-0000-000000000002','Dan Driver','driver@demo.parkspace.test', false, 'verified');
insert into vehicles (user_id, plate, make, model, size) values
  ('00000000-0000-0000-0000-000000000002','AB12 CDE','Ford','Focus','medium');
insert into listings (id, host_id, title, address, postcode, latitude, longitude, price_hour, price_day, status) values
  ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','Driveway near Kings Cross','12 Example Rd','N1 9AA',51.5308,-0.1238,2.50,14.00,'live'),
  ('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001','Garage near Euston','5 Sample St','NW1 2AA',51.5282,-0.1337,3.00,18.00,'live');
