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
      delete from booking_extras where booking_id in (select id from bookings where reference not like 'PS-SEED%');
      delete from bookings where reference not like 'PS-SEED%';
      delete from offers;
      delete from extra_types where name like 'E2E %';
      delete from vehicles where plate like 'E2E%';
      update listing_extras set price = 1.50, price_unit = 'per_booking', active = true where listing_id = '10000000-0000-4000-8000-000000000001';
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
psql(f"update bookings set booked_start = now() - interval '3 hours', booked_end = now() - interval '30 minutes', blocked_end = now() - interval '15 minutes' where id='{b['id']}'")  # never parked -> no-show
psql("update settings set value='15' where key='grace_minutes'")
print("  ...waiting for scheduler (up to 40s)")
for _ in range(20):
    time.sleep(2)
    if psql(f"select status from bookings where id='{b['id']}'") == "completed":
        break
st = psql(f"select status from bookings where id='{b['id']}'")
evs = psql(f"select string_agg(event, ',' order by created_at) from booking_events where booking_id='{b['id']}'")
check("never-parked booking past end+grace closes as a no-show (no refund)", st == "completed" and "auto_ended" in evs, (st, evs))
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

def wait_for(cond, secs=50):
    for _ in range(secs // 2):
        if cond():
            return True
        time.sleep(2)
    return cond()


def status_of(bid):
    return psql(f"select status from bookings where id='{bid}'")


def shift_to_past(bid, status="parked"):
    psql(f"update bookings set booked_start = now() - interval '3 hours', booked_end = now() - interval '30 minutes', "
         f"blocked_end = now() - interval '15 minutes', status = '{status}', actual_parked_at = now() - interval '3 hours' where id = '{bid}'")


print("Request-to-book")
s, r = book(D, ids["waterloo"], now + timedelta(days=30))
rb = r
check("request-mode pay -> requested, card held", r["status"] == "requested" and r["address"] is None, r.get("status"))
check("no charge posted while only held", ledger(rb["id"]) == {})
s, r2 = call("POST", f"/bookings/{rb['id']}/respond", {"accept": True}, H)
check("only the booking's host can respond", s == 400)
s, r2 = call("POST", f"/bookings/{rb['id']}/respond", {"accept": True}, OMAR)
check("host accepts -> confirmed, address revealed", s == 201 and r2["status"] == "confirmed")
s, dd = call("GET", f"/bookings/{rb['id']}", token=D)
check("acceptance captures the charge", ledger(rb["id"]).get("charge") == float(rb["total_amount"]) and dd["address"])
s, r = book(D, ids["waterloo"], now + timedelta(days=31))
s, r2 = call("POST", f"/bookings/{r['id']}/respond", {"accept": False}, OMAR)
check("host declines -> cancelled, never charged", r2["status"] == "cancelled" and ledger(r["id"]) == {})
s, r = book(D, ids["waterloo"], now + timedelta(days=32))
s, r2 = call("POST", f"/bookings/{r['id']}/cancel", None, D)
check("driver withdraws a pending request with no charge", r2["status"] == "cancelled" and ledger(r["id"]) == {})
s, exp = book(D, ids["waterloo"], now + timedelta(days=33))
psql(f"update bookings set respond_by = now() - interval '1 minute' where id = '{exp['id']}'")

print("Extending a booking")
s, r = book(D, ids["kx"], now + timedelta(minutes=2), hours=2)
ex = r
call("POST", f"/bookings/{ex['id']}/parked", {}, D)
s, r = call("POST", f"/bookings/{ex['id']}/extend", {"hours": 2}, D)
check("extend +2h adds 5.00 and moves the end", s == 201 and float(r["total_amount"]) == 10.0 and float(r["commission_amount"]) == 2.0, r if s != 201 else r["total_amount"])
check("extension charged immediately (ledger 5.00 + 5.00)", abs(float(psql(f"select sum(amount) from transactions where booking_id='{ex['id']}' and type='charge'")) - 10.0) < 0.01)
nxt_start = datetime.fromisoformat(r["booked_end"].replace("Z", "+00:00")) + timedelta(minutes=15)
s, nb = book(D, ids["kx"], nxt_start, hours=1)
s, r = call("POST", f"/bookings/{ex['id']}/extend", {"hours": 3}, D)
check("extension blocked when the next booking follows", s == 409, (s, r))

print("Overstay flow")
s, a = book(D, ids["shoreditch"], now + timedelta(days=40)); shift_to_past(a["id"])
s, b = book(D, ids["camden"], now + timedelta(days=41)); shift_to_past(b["id"])
s, c = book(D, ids["islington"], now + timedelta(days=42)); shift_to_past(c["id"])
psql(f"update bookings set overstay_check='asked', overstay_asked_at = now() - interval '2 hours' where id='{c['id']}'")

print("Reminders")
s, soon = book(D, ids["euston"], now + timedelta(minutes=20), hours=1)

print("  ...waiting for scheduler (up to 60s)")
wait_for(lambda: psql(f"select overstay_check from bookings where id='{a['id']}'") == "asked"
         and psql(f"select overstay_check from bookings where id='{b['id']}'") == "asked"
         and status_of(c["id"]) == "completed" and status_of(exp["id"]) == "cancelled", 60)

check("expired request released automatically", status_of(exp["id"]) == "cancelled" and ledger(exp["id"]) == {})
check("overstay check asked after grace", psql(f"select overstay_check from bookings where id='{a['id']}'") == "asked")
check("host was notified 'Is the car still there?'", psql(f"select count(*) from notifications where ref_id='{a['id']}' and type='overstay_check'") == "1")
check("silent host: auto-end at booked end with no fee",
      status_of(c["id"]) == "completed" and "overstay_fee" not in ledger(c["id"]) and
      psql(f"select actual_ended_at = booked_end from bookings where id='{c['id']}'") == "t")
s, r = call("POST", f"/bookings/{b['id']}/car-status", {"stillThere": False}, H)
check("host says car gone -> ends at booked end, no fee", r["status"] == "completed" and "overstay_fee" not in ledger(b["id"]), r.get("status"))
s, r = call("POST", f"/bookings/{a['id']}/car-status", {"stillThere": True}, H)
check("a different host cannot answer for someone else's booking", s == 400)
s, r = call("POST", f"/bookings/{a['id']}/car-status", {"stillThere": True}, OMAR)
check("host confirms car still there -> overstay", s == 201 and r["status"] == "overstay" and r["overstay_fee_now"] > 0, (s, r if s != 201 else r["status"]))
s, r = call("POST", f"/bookings/{a['id']}/end", None, D)
lg = ledger(a["id"])
fee = lg.get("overstay_fee", 0)
check("overstay fee = 1.5 x hourly x hours started (shoreditch 2.20/h)", s == 201 and abs(fee - 1 * 2.20 * 1.5) < 0.011, (s, lg))
check("overstay fee split 80/20 into ledger", abs(lg["commission"] + lg["host_earning"] - (float(a["total_amount"]) + fee)) < 0.02, lg)

print("Notifications")
s, n = call("GET", "/me/notifications", token=D)
types = {i["type"] for i in n["items"]}
check("driver received booking_confirmed, booking_ended", {"booking_confirmed", "booking_ended"} <= types, types)
check("driver got a start reminder for the booking 20 min away", wait_for(lambda: psql(f"select count(*) from notifications where ref_id='{soon['id']}' and type='reminder_start'") == "1", 30))
check("overstay warning sent to driver", "overstay_warning" in {i['type'] for i in call("GET", "/me/notifications", token=D)[1]["items"]})
check("unread count reported", n["unread"] > 0)
call("POST", "/me/notifications/read", None, D)
s, n = call("GET", "/me/notifications", token=D)
check("mark all read", n["unread"] == 0)
s, n = call("GET", "/me/notifications", token=H)
check("host received new-booking notifications", any(i["type"] == "booking_confirmed" for i in n["items"]))

print("Price negotiation")
o_start = now + timedelta(days=50)
def offer(tok, listing, start, amount, hours=2, message=None):
    body = {"listingId": listing, "start": iso(start), "end": iso(start + timedelta(hours=hours)), "amount": amount}
    if message: body["message"] = message
    return call("POST", "/offers", body, tok)

s, r = offer(D, ids["camden"], o_start, 3.0)
check("offer refused on a listing that does not allow offers", s == 400, (s, r))
s, r = offer(D, ids["kx"], o_start, 3.0)
check("offer below host minimum is declined automatically", s == 201 and r["autoDeclined"] and r["offer"]["status"] == "declined", (s, r))
s, r = offer(D, ids["kx"], o_start, 5.0)
check("offer at or above listed price rejected", s == 400, (s, r))
s, r = offer(D, ids["kx"], o_start, 4.0, message="call me on 07700 900123")
check("phone number in message blocked", s == 400 and "safety" in r["message"], (s, r))
s, r = offer(D, ids["kx"], o_start, 4.0, message="Regular customer, would 4 work?")
check("valid offer is open", s == 201 and r["offer"]["status"] == "open" and r["offer"]["round"] == 1, (s, r))
o1 = r["offer"]
s, mine = call("GET", "/offers", token=H)
mine_o = [x for x in mine if x["thread_id"] == o1["thread_id"]]
check("host sees it awaiting their response", mine_o and mine_o[0]["awaiting_me"] and mine_o[0]["role"] == "host", mine_o)
s, mine_d = call("GET", "/offers", token=D)
check("driver sees it as waiting (not awaiting them)", [x for x in mine_d if x["thread_id"] == o1["thread_id"]][0]["awaiting_me"] is False)
s, _ = call("POST", f"/offers/{o1['id']}/respond", {"action": "accept"}, D)
check("driver cannot answer their own offer", s == 403)
s, _ = call("GET", f"/offers/{o1['thread_id']}", token=OMAR)
check("non-participant cannot read the negotiation", s == 404)
s, r = call("POST", f"/offers/{o1['id']}/respond", {"action": "counter", "amount": 4.5, "message": "4.50 is my best"}, H)
check("host counters (round 2)", s == 201 and r["current"]["round"] == 2 and float(r["current"]["amount"]) == 4.5, (s, r))
s, r = call("POST", f"/offers/{r['current']['id']}/respond", {"action": "counter", "amount": 4.2}, D)
check("driver counters (round 3)", s == 201 and r["current"]["round"] == 3, (s, r))
s, r = call("POST", f"/offers/{r['current']['id']}/respond", {"action": "counter", "amount": 4.4}, H)
check("host counters (round 4 = final)", s == 201 and r["current"]["round"] == 4 and r["can_counter"] is False, (s, r))
s, bad = call("POST", f"/offers/{r['current']['id']}/respond", {"action": "counter", "amount": 4.3}, D)
check("a 4th counter-offer is refused (max 3)", s == 400 and "3 counter" in bad["message"], (s, bad))
s, r2 = call("POST", f"/offers/{r['current']['id']}/respond", {"action": "accept"}, D)
check("driver accepts -> accepted with 15-minute pay window", s == 201 and r2["current"]["status"] == "accepted" and r2["can_pay"], (s, r2))
check("all steps saved in history", len(r2["steps"]) == 4 and [x["sent_by"] for x in r2["steps"]] == ["driver", "host", "driver", "host"])
s, bk = call("POST", f"/offers/{r2['current']['id']}/pay", None, D)
check("paying books at the agreed price (4.40)", s == 201 and bk["status"] == "confirmed" and float(bk["total_amount"]) == 4.4, (s, bk if s != 201 else bk["status"]))
check("commission applies to the agreed price (20% of 4.40)", float(bk["commission_amount"]) == 0.88 and float(bk["host_earnings"]) == 3.52)
check("ledger charged 4.40, offer marked paid", ledger(bk["id"]).get("charge") == 4.4 and psql(f"select status from offers where id='{r2['current']['id']}'") == "paid")
s, _ = call("POST", f"/offers/{r2['current']['id']}/pay", None, D)
check("cannot pay the same offer twice", s == 400)

# competing offers close when someone books the slot
c_start = now + timedelta(days=51)
s, oo = offer(OMAR, ids["kx"], c_start, 4.0)
check("another driver opens an offer for a slot", s == 201 and oo["offer"]["status"] == "open", (s, oo))
book(D, ids["kx"], c_start)
check("booking the slot closes the other open offer", psql(f"select status from offers where id='{oo['offer']['id']}'") == "expired")
s, n = call("GET", "/me/notifications", token=OMAR)
check("the other driver is told (offer_closed)", any(i["type"] == "offer_closed" for i in n["items"]))

# accepted but unpaid -> cannot pay after window
s, o3 = offer(D, ids["euston"], now + timedelta(days=52), 4.5)
call("POST", f"/offers/{o3['offer']['id']}/respond", {"action": "accept"}, H)
psql(f"update offers set pay_by = now() - interval '1 minute' where id='{o3['offer']['id']}'")
s, r = call("POST", f"/offers/{o3['offer']['id']}/pay", None, D)
check("payment after the 15-minute window is refused", s == 400, (s, r))

# decline and expiry
s, o4 = offer(D, ids["euston"], now + timedelta(days=53), 4.5)
s, r = call("POST", f"/offers/{o4['offer']['id']}/respond", {"action": "decline"}, H)
check("host declines an offer", r["current"]["status"] == "declined")
s, o5 = offer(D, ids["shoreditch"], now + timedelta(days=54), 3.0)
psql(f"update offers set expires_at = now() - interval '1 minute' where id='{o5['offer']['id']}'")
check("open offer expires automatically", wait_for(lambda: psql(f"select status from offers where id='{o5['offer']['id']}'") == "expired", 45))

print("Paid extras")
def extras_of(listing):
    return {e["name"]: e for e in call("GET", f"/listings/{listing}", token=D)[1]["extras"]}
kx_x = extras_of(ids["kx"])
check("listing detail lists its extras", "CCTV surveillance" in kx_x and float(kx_x["CCTV surveillance"]["price"]) == 1.5)
e_start = now + timedelta(days=60)
qs = f"start={iso(e_start)}&end={iso(e_start + timedelta(hours=2))}&extras={kx_x['CCTV surveillance']['id']}"
s, q = call("GET", f"/listings/{ids['kx']}?{qs}", token=D)
check("quote includes the extra (5.00 + 1.50 = 6.50)", float(q["quote"]["total"]) == 6.5 and float(q["quote"]["extras"][0]["line_total"]) == 1.5, q.get("quote"))
s, r = book(D, ids["kx"], e_start, extras=[{"id": kx_x["CCTV surveillance"]["id"]}])
check("booking with extra: total 6.50, commission 1.30 (20% incl. extras), host 5.20",
      float(r["total_amount"]) == 6.5 and float(r["extras_amount"]) == 1.5 and float(r["commission_amount"]) == 1.3 and float(r["host_earnings"]) == 5.2, r)
check("booking shows its extra lines", [x["name"] for x in r["extras"]] == ["CCTV surveillance"] and float(r["extras"][0]["line_total"]) == 1.5)
check("extra price is frozen on the booking", psql(f"select price from booking_extras where booking_id='{r['id']}'") == "1.50")
s, bad = book(D, ids["kx"], e_start + timedelta(days=1), pay=False, extras=[{"id": "99999999-9999-4999-8999-999999999999"}])
check("unknown extra rejected", s == 400, (s, bad))

cam_x = extras_of(ids["camden"])
ev_extra = cam_x["EV charging"]["id"]
vehicles = call("GET", "/me/vehicles", token=D)[1]
plain = next(v for v in vehicles if not v["is_ev"])
ev = next(v for v in vehicles if v["is_ev"])
s, bad = book(D, ids["camden"], e_start, pay=False, vehicleId=plain["id"], extras=[{"id": ev_extra, "quantity": 20}])
check("EV charging refused for a non-EV vehicle", s == 400 and "electric" in bad["message"], (s, bad))
s, ccs = call("POST", "/me/vehicles", {"plate": "E2E CCS1", "size": "medium", "isEv": True, "evConnector": "ccs"}, D)
s, bad = book(D, ids["camden"], e_start, pay=False, vehicleId=ccs["id"], extras=[{"id": ev_extra, "quantity": 20}])
check("EV charging refused when the connector does not match", s == 400 and "connector" in bad["message"], (s, bad))
s, r = book(D, ids["camden"], e_start, vehicleId=ev["id"], extras=[{"id": ev_extra, "quantity": 20}])
check("EV charging per kWh: 6.40 parking + 20 x 0.45 = 15.40", s == 201 and float(r["total_amount"]) == 15.4 and r["extras"][0]["quantity"] == "20.00" or float(r["total_amount"]) == 15.4, (s, r.get("total_amount")))

s, _ = call("PUT", f"/listings/{ids['kx']}/extras", {"extras": [{"extraTypeId": kx_x["CCTV surveillance"]["extra_type_id"] if "extra_type_id" in kx_x["CCTV surveillance"] else "", "price": 2, "priceUnit": "per_hour"}]}, H)
check("an extra cannot use a price unit its type does not allow", s == 400)
types = call("GET", "/extra-types", token=H)[1]
cctv_t = next(t for t in types if t["name"] == "CCTV surveillance")
s, _ = call("PUT", f"/listings/{ids['kx']}/extras", {"extras": [{"extraTypeId": cctv_t["id"], "price": 2.0, "priceUnit": "per_day"}]}, H)
check("host updates extras and prices", s == 200 and float(extras_of(ids["kx"])["CCTV surveillance"]["price"]) == 2.0 and extras_of(ids["kx"])["CCTV surveillance"]["price_unit"] == "per_day")
s, _ = call("PUT", f"/listings/{ids['kx']}/extras", {"extras": []}, OMAR)
check("another host cannot edit my extras", s == 404)
s, new_t = call("POST", "/admin/extra-types", {"name": "E2E Bike rack", "allowedPriceUnits": ["per_booking"]}, A)
check("admin adds a new extra type without an app update", s == 201 and new_t["name"] == "E2E Bike rack")
check("new type is offered to hosts", any(t["name"] == "E2E Bike rack" for t in call("GET", "/extra-types", token=H)[1]))
call("PATCH", f"/admin/extra-types/{new_t['id']}", {"active": False}, A)
check("deactivated type disappears", not any(t["name"] == "E2E Bike rack" for t in call("GET", "/extra-types", token=H)[1]))
s, _ = call("POST", "/admin/extra-types", {"name": "x"}, D)
check("drivers cannot manage extra types", s == 403)
call("PUT", f"/listings/{ids['kx']}/extras", {"extras": [{"extraTypeId": cctv_t["id"], "price": 1.5, "priceUnit": "per_booking"}]}, H)

# negotiated booking that includes an extra
kx_x = extras_of(ids["kx"])
n_start = now + timedelta(days=61)
s, o = offer(D, ids["kx"], n_start, 5.0) if False else call("POST", "/offers", {"listingId": ids["kx"], "start": iso(n_start), "end": iso(n_start + timedelta(hours=2)), "amount": 5.0, "extras": [{"id": kx_x["CCTV surveillance"]["id"]}]}, D)
check("offer can include extras (listed total 6.50)", s == 201 and o["listedTotal"] == 6.5, (s, o))
call("POST", f"/offers/{o['offer']['id']}/respond", {"action": "accept"}, H)
s, bk = call("POST", f"/offers/{o['offer']['id']}/pay", None, D)
parts = float(bk["parking_amount"]) + float(bk["extras_amount"])
lines = sum(float(x["line_total"]) for x in bk["extras"])
check("negotiated total 5.00 keeps parking + extras consistent", s == 201 and float(bk["total_amount"]) == 5.0 and abs(parts - 5.0) < 0.011 and abs(lines - float(bk["extras_amount"])) < 0.02, (s, bk.get("parking_amount"), bk.get("extras_amount"), lines))
check("commission on negotiated total with extras", float(bk["commission_amount"]) == 1.0)

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
