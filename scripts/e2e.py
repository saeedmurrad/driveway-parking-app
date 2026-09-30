#!/usr/bin/env python3
"""End-to-end API checks against the running docker stack (spec section 16 acceptance tests).
Usage: docker compose up -d && python3 scripts/e2e.py
"""
import json, subprocess, sys, time, threading, urllib.request, urllib.error
from datetime import datetime, timedelta, timezone

API = "http://localhost:3000"
PW = "demo1234"
ids = {
    "kx": "10000000-0000-4000-8000-000000000001",   # flexible
    "euston": "10000000-0000-4000-8000-000000000002",  # moderate
    "bloom": "10000000-0000-4000-8000-000000000003",   # strict
    "camden": "10000000-0000-4000-8000-000000000004",
    "islington": "10000000-0000-4000-8000-000000000005",
    "shoreditch": "10000000-0000-4000-8000-000000000006",
    "waterloo": "10000000-0000-4000-8000-000000000007",
}
passed = failed = 0


def call(method, path, body=None, token=None):
    req = urllib.request.Request(API + path, method=method, data=json.dumps(body or {}).encode() if method != "GET" else None,
                                 headers={"content-type": "application/json", **({"authorization": f"Bearer {token}"} if token else {})})
    try:
        with urllib.request.urlopen(req) as r:
            t = r.read().decode()
            return r.status, (json.loads(t) if t else None)
    except urllib.error.HTTPError as e:
        t = e.read().decode()
        return e.code, (json.loads(t) if t else None)


def login(email):
    return call("POST", "/auth/login", {"email": email, "password": PW})[1]["token"]


def psql(sql):
    out = subprocess.run(["docker", "compose", "exec", "-T", "db", "psql", "-U", "postgres", "-d", "parkspace", "-At", "-c", sql],
                         capture_output=True, text=True)
    if out.returncode:
        raise RuntimeError(out.stderr)
    return out.stdout.strip()


def check(name, cond, detail=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  PASS  {name}")
    else:
        failed += 1
        print(f"  FAIL  {name}  {detail}")


def iso(dt):
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:00Z")


def book(token, listing, start, hours=2, pay=True, **extra):
    end = start + timedelta(hours=hours)
    s, b = call("POST", "/bookings", {"listingId": listing, "start": iso(start), "end": iso(end), **extra}, token)
    if s != 201 or not pay:
        return s, b
    s2, d = call("POST", f"/bookings/{b['booking']['id']}/pay", None, token)
    return s2, d


def ledger(bid):
    rows = psql(f"select type||':'||amount from transactions where booking_id='{bid}' order by created_at, type")
    out = {}
    for r in rows.splitlines():
        t, a = r.split(":")
        out[t] = out.get(t, 0) + float(a)
    return out


def reset():
    """Make the run repeatable: remove rows created by earlier runs, keep the seed data."""
    psql("""
      delete from transactions where booking_id in (select id from bookings where reference not like 'PS-SEED%') or type = 'payout';
      delete from booking_events where booking_id in (select id from bookings where reference not like 'PS-SEED%');
      delete from reviews where booking_id in (select id from bookings where reference not like 'PS-SEED%');
      delete from bookings where reference not like 'PS-SEED%';
      delete from payouts; delete from availability_blocks;
      delete from availability_rules where listing_id <> '10000000-0000-4000-8000-000000000003';
      update listings set cancellation_policy = 'strict' where id = '10000000-0000-4000-8000-000000000005';
      update settings set value = '0.20' where key = 'commission_rate';
    """)


reset()
now = datetime.now(timezone.utc)
D, H, A = login("driver@demo.parkspace.test"), login("host@demo.parkspace.test"), login("admin@demo.parkspace.test")
OMAR = login("omar@demo.parkspace.test")

print("Auth & permissions")
s, _ = call("GET", "/me/bookings")
check("unauthenticated request rejected", s == 401)
s, _ = call("GET", "/admin/stats", token=D)
check("driver cannot reach admin API", s == 403)
s, r = call("POST", "/auth/register", {"name": "Test User", "email": f"t{int(time.time())}@x.test", "password": "secret12"})
check("register returns token", s == 201 and r.get("token"))

print("Acceptance: price, address hiding, lifecycle")
start = now + timedelta(minutes=5)
s, b = book(D, ids["kx"], start, pay=False)
check("booking created pending_payment", s == 201 and b["booking"]["status"] == "pending_payment")
bid = b["booking"]["id"]
s, det = call("GET", f"/bookings/{bid}", token=D)
check("address hidden before payment", det["address"] is None)
s, det = call("POST", f"/bookings/{bid}/pay", None, D)
check("paid -> confirmed, address revealed", det["status"] == "confirmed" and det["address"])
check("total 2h x 2.50 = 5.00; commission 1.00; host 4.00",
      float(det["total_amount"]) == 5.0 and float(det["commission_amount"]) == 1.0 and float(det["host_earnings"]) == 4.0)
s, _ = call("POST", f"/bookings/{bid}/parked", {}, D)
check("I've Parked works in window", s == 201)
s, det = call("POST", f"/bookings/{bid}/end", None, D)
check("End Booking completes", det["status"] == "completed" and det["actual_parked_at"] and det["actual_ended_at"])
lg = ledger(bid)
check("ledger: charge 5.00, commission 1.00, host_earning 4.00", lg == {"charge": 5.0, "commission": 1.0, "host_earning": 4.0}, lg)
s, _ = call("POST", f"/bookings/{bid}/cancel", None, D)
check("cannot cancel a completed booking", s == 400)

print("Acceptance: two drivers, same slot")
slot = now + timedelta(days=5)
res = []
def go(tok):
    res.append(book(tok, ids["waterloo"], slot, pay=False)[0])
ts = [threading.Thread(target=go, args=(t,)) for t in (D, H)]
[t.start() for t in ts]; [t.join() for t in ts]
check("exactly one of two simultaneous bookings wins (201 + 409)", sorted(res) == [201, 409], res)

print("Acceptance: cancellation refunds follow policy, commission proportional")
def cancel_case(label, listing, start_off_h, age_booking, expect_pct, who=D):
    s, b = book(D, listing, now + timedelta(hours=start_off_h), hours=2)
    bid = b["id"]
    if age_booking:
        psql(f"update bookings set created_at = now() - interval '1 hour' where id='{bid}'")
    s, r = call("POST", f"/bookings/{bid}/cancel", None, who)
    total = float(b["total_amount"])
    lg = ledger(bid)
    refund = lg.get("refund", 0)
    kept = total - refund
    ok = s == 201 and abs(refund - total * expect_pct / 100) < 0.011
    if kept > 0:
        ok = ok and abs(lg.get("commission", 0) - kept * 0.2) < 0.011 and abs(lg.get("commission", 0) + lg.get("host_earning", 0) - kept) < 0.011
    else:
        ok = ok and "commission" not in lg and "host_earning" not in lg
    check(f"{label}: {expect_pct}% refund, ledger balances", ok, (s, lg))

cancel_case("moderate, 40h out", ids["euston"], 40, True, 100)
cancel_case("moderate, 10h out", ids["euston"], 10, True, 50)
cancel_case("moderate, 0.5h out", ids["euston"], 0.5, True, 0)
cancel_case("strict, 30h out", ids["islington"], 30, True, 50)
cancel_case("strict, 10h out", ids["islington"], 10, True, 0)
cancel_case("flexible, 3h out", ids["camden"], 3, True, 100)
cancel_case("mistake protection (cancel within 5 min, strict, 2h out)", ids["islington"], 2, False, 100)
s, b = book(D, ids["shoreditch"], now + timedelta(hours=1))
s, r = call("POST", f"/bookings/{b['id']}/cancel", None, OMAR)
lg = ledger(b["id"])
check("host cancel -> driver refunded in full", s == 201 and abs(lg.get("refund", 0) - float(b["total_amount"])) < 0.01, lg)
s, r = call("POST", f"/bookings/{b['id']}/cancel", None, H)
check("unrelated user cannot cancel someone else's booking", s == 404)

print("Acceptance: auto-end after grace")
s, b = book(D, ids["kx"], now + timedelta(days=9))
call("POST", f"/bookings/{b['id']}/parked", {}, D)  # not allowed yet (too early) -> expected 400
psql(f"update bookings set booked_start = now() - interval '3 hours', booked_end = now() - interval '30 minutes', blocked_end = now() - interval '15 minutes', status='parked', actual_parked_at = now() - interval '3 hours' where id='{b['id']}'")
psql("update settings set value='15' where key='grace_minutes'")
print("  ...waiting for scheduler (up to 40s)")
for _ in range(20):
    time.sleep(2)
    if psql(f"select status from bookings where id='{b['id']}'") == "completed":
        break
st = psql(f"select status from bookings where id='{b['id']}'")
evs = psql(f"select string_agg(event, ',' order by created_at) from booking_events where booking_id='{b['id']}'")
check("parked booking past end+grace auto-ends", st == "completed" and "auto_ended" in evs, (st, evs))
check("auto-end posts commission + host earning", set(ledger(b["id"])) >= {"commission", "host_earning"})

print("Acceptance: expired unpaid booking frees the slot")
s, b = book(D, ids["islington"], now + timedelta(days=11), pay=False)
psql(f"update bookings set created_at = now() - interval '20 minutes' where id='{b['booking']['id']}'")
for _ in range(20):
    time.sleep(2)
    if psql(f"select status from bookings where id='{b['booking']['id']}'") == "cancelled":
        break
check("unpaid booking cancelled after timeout", psql(f"select status from bookings where id='{b['booking']['id']}'") == "cancelled")

print("Acceptance: payouts after dispute window")
s, sm = call("GET", "/me/host-summary", token=H)
check("host has available balance (seeded history)", sm["available"] > 10, sm)
avail = sm["available"]
s, p = call("POST", "/me/payout", None, H)
check("payout succeeds", s == 201 and abs(float(p["amount"]) - avail) < 0.01, (s, p))
s, sm2 = call("GET", "/me/host-summary", token=H)
check("available drops to 0, paid out rises", sm2["available"] == 0 and abs(sm2["paidOut"] - avail) < 0.01, sm2)
check("payout appears in history", len(sm2["payouts"]) >= 1)
s, _ = call("POST", "/me/payout", None, H)
check("second payout below minimum rejected", s == 400)

print("Acceptance: totals equal sum of transactions")
s, ds = call("GET", "/me/driver-summary", token=D)
db_total = float(psql("select coalesce(sum(case when type='refund' then -amount else amount end),0) from transactions where user_id='00000000-0000-4000-8000-000000000002' and type in ('charge','refund','overstay_fee')"))
check("driver all-time spend == ledger sum", abs(ds["allTime"] - db_total) < 0.01, (ds, db_total))
s, sm = call("GET", "/me/host-summary", token=H)
db_earn = float(psql("select coalesce(sum(amount),0) from transactions where user_id='00000000-0000-4000-8000-000000000001' and type='host_earning'"))
check("host all-time earned == ledger sum", abs(sm["allTime"] - db_earn) < 0.01, (sm, db_earn))

print("Acceptance: commission change applies to new bookings only")
s, old = book(D, ids["camden"], now + timedelta(days=13))
s, _ = call("PUT", "/admin/settings", {"key": "commission_rate", "value": "0.25"}, A)
check("admin can set commission", s == 200)
s, new = book(D, ids["camden"], now + timedelta(days=14))
s, o2 = call("GET", f"/bookings/{old['id']}", token=D)
check("new booking uses 25%, old keeps 20%", float(new["commission_rate"]) == 0.25 and float(o2["commission_rate"]) == 0.2)
call("PUT", "/admin/settings", {"key": "commission_rate", "value": "0.2"}, A)
s, _ = call("PUT", "/admin/settings", {"key": "commission_rate", "value": "0.9"}, A)
check("commission outside 0-50% rejected", s == 400)

print("Availability, blocks, editing, stay limits")
# Bloomsbury is open Mon-Fri 07:00-19:00 UK time only
d = now + timedelta(days=1)
while d.astimezone(timezone(timedelta(hours=0))).weekday() != 1:  # next Tuesday (UTC weekday; times below are well inside the window either way)
    d += timedelta(days=1)
tue_noon = d.replace(hour=12, minute=0, second=0, microsecond=0)
s, r = book(D, ids["bloom"], tue_noon, hours=2, pay=False)
check("booking inside weekly hours allowed", s == 201, r)
s, r = book(D, ids["bloom"], tue_noon.replace(hour=22), hours=2, pay=False)
check("booking outside weekly hours rejected", s == 400, (s, r))
sat = tue_noon + timedelta(days=4)
s, r = book(D, ids["bloom"], sat, hours=2, pay=False)
check("booking on a closed day rejected", s == 400, (s, r))
s, res = call("GET", f"/listings/search?lat=51.5246&lng=-0.1256&vehicleSize=small&start={iso(tue_noon + timedelta(days=7))}&end={iso(tue_noon + timedelta(days=7, hours=2))}", token=D)
check("search includes it inside hours", any(x["id"] == ids["bloom"] for x in res))
s, res = call("GET", f"/listings/search?lat=51.5246&lng=-0.1256&vehicleSize=small&start={iso(sat + timedelta(days=7))}&end={iso(sat + timedelta(days=7, hours=2))}", token=D)
check("search excludes it on closed day", not any(x["id"] == ids["bloom"] for x in res))

# host edits availability + blocks on Helen's Camden space
s, _ = call("PUT", f"/listings/{ids['camden']}/availability", {"always": False, "rules": [{"dayOfWeek": i, "start": "08:00", "end": "20:00"} for i in range(7)]}, H)
check("host sets weekly availability", s == 200)
s, av = call("GET", f"/listings/{ids['camden']}/availability", token=H)
check("availability readable", av["always"] is False and len(av["rules"]) == 7)
s, _ = call("PUT", f"/listings/{ids['camden']}/availability", {"always": False, "rules": [{"dayOfWeek": 1, "start": "10:00", "end": "09:00"}]}, H)
check("inverted window rejected", s == 400)
s, _ = call("PUT", f"/listings/{ids['camden']}/availability", {"always": True}, OMAR)
check("another host cannot edit availability", s == 404)
call("PUT", f"/listings/{ids['camden']}/availability", {"always": True}, H)
blk_start = now + timedelta(days=20)
s, blk = call("POST", f"/listings/{ids['camden']}/blocks", {"start": iso(blk_start), "end": iso(blk_start + timedelta(hours=6)), "reason": "Family visit"}, H)
check("host blocks a date range", s == 201)
s, r = book(D, ids["camden"], blk_start + timedelta(hours=1), hours=1, pay=False)
check("blocked time cannot be booked", s == 400, (s, r))
call("DELETE", f"/listings/{ids['camden']}/blocks/{blk['id']}", None, H)
s, r = book(D, ids["camden"], blk_start + timedelta(hours=1), hours=1, pay=False)
check("unblocked time can be booked", s == 201, (s, r))
s, bk = book(D, ids["camden"], now + timedelta(days=22), pay=True)
s, r = call("POST", f"/listings/{ids['camden']}/blocks", {"start": iso(now + timedelta(days=22)), "end": iso(now + timedelta(days=22, hours=4))}, H)
check("cannot block over an existing booking", s == 409, (s, r))

s, r = call("PATCH", f"/listings/{ids['kx']}", {"priceHour": 2.75, "title": "Driveway near King's Cross"}, H)
check("host edits listing price", s == 200 and float(r["price_hour"]) == 2.75)
s, _ = call("PATCH", f"/listings/{ids['kx']}", {"priceHour": 2.5}, OMAR)
check("other host cannot edit my listing", s == 404)
call("PATCH", f"/listings/{ids['kx']}", {"priceHour": 2.5}, H)
s, r = book(D, ids["kx"], now + timedelta(days=25), hours=1000, pay=False)
check("stay over the max is rejected", s == 400, (s, r))

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
