#!/usr/bin/env python3
"""Builds docs/demo-guide.html from the screenshots in docs/demo-screenshots.
Then print it to PDF with Chrome:
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --no-pdf-header-footer \
     --print-to-pdf=docs/ParkSpace-Demo-Guide.pdf file://$PWD/docs/demo-guide.html
"""
import html, os

HERE = os.path.dirname(os.path.abspath(__file__))

# (image, who, title, what you see, what to say)
SECTIONS = [
 ("1. Sign in and find a space", "The driver's journey starts here. About 3 minutes.", [
  ("01-login", "Anyone", "Welcome screen",
   "Sign in, create an account, or tap a demo role (Driver, Host, Admin).",
   "One app for drivers, hosts and the platform team. Demo buttons let anyone try each role in one tap."),
  ("02-explore", "Driver", "Find a space on the map",
   "A live map with price pins and photo cards sorted by distance, with tags for Offers and Request-to-book. Filters for time, duration, covered, CCTV, EV and price.",
   "Drivers see nearby spaces they can actually book for their chosen time. Spaces already booked don't appear."),
  ("03-space-detail", "Driver", "Space details",
   "Photo gallery, rating, features, the booking time and the driver's vehicle. Make an offer or Book now.",
   "Everything needed to decide, in one screen. The exact address stays hidden until payment."),
  ("04-extras-price", "Driver", "Paid extras and live price",
   "Ticking CCTV reprices the stay on the server: £5.00 parking + £1.50 extra = £6.50. No service fee.",
   "Hosts earn more from add-ons like CCTV, EV charging or a car wash, and the commission applies to the full total."),
  ("05-checkout", "Driver", "Confirm and pay",
   "A payment sheet with the stay, the vehicle and a test card. Payment is simulated in this proof of concept.",
   "In production this is Stripe (cards, Apple Pay, Google Pay) with the platform fee split automatically."),
  ("06-booking-confirmed", "Driver", "Booking confirmed, address revealed",
   "A confirmed booking shows the exact address, access instructions and a link to open maps.",
   "Only after payment does the driver get where to park. The booking has a reference and its own timeline."),
 ]),
 ("2. During the stay", "I've parked, chat, extend, end and rate. About 3 minutes.", [
  ("07-parked-dialog", "Driver", "I've parked",
   "Tapping it offers an optional photo of the parked car. The phone's location is also recorded if the driver allows it.",
   "A time-stamped check-in protects both sides in a damage dispute. A warning shows if the driver is more than about 200 m away."),
  ("08-parked-state", "Driver", "Active booking",
   "The booking is now Parked. The driver can End booking, Extend, chat with the host, view a receipt or report a problem.",
   "Everything the driver needs while parked is in one place."),
  ("09-chat", "Driver", "In-app chat",
   "A message to the host appears instantly and the host is notified.",
   "Chat opens only once a booking is confirmed, and is saved in case of a dispute."),
  ("10-extend", "Driver", "Extend the stay",
   "Choose +1, +2 or +4 hours. Extra time is charged straight away at the hourly rate, if the space is free.",
   "A driver running late can extend in two taps, unless the next booking is right behind them."),
  ("11-completed", "Driver", "Booking ended",
   "The stay is Completed with booked and actual times. The extension added £2.50 to the parking: £9.00 total.",
   "History always shows booked versus actual times, and nothing is ever deleted."),
  ("12-rating", "Driver", "Rate the space",
   "A five-star rating with an optional comment.",
   "Ratings feed the space's score. Hosts rate drivers too, and hosts see a driver's rating on requests and offers."),
  ("13-timeline", "Driver", "Receipt, chat and timeline",
   "Receipt, Report a problem and Book again buttons, plus a timestamped timeline: created, paid, confirmed, parked, extended, ended.",
   "The timeline is the single source of truth for disputes: who did what, and when."),
  ("14-receipt", "Driver", "Receipt",
   "An itemised receipt with parking, extras and the total charged.",
   "A copy is emailed in production. Hosts get an earnings statement per booking instead."),
 ]),
 ("3. History and spending", "Totals come from the payment ledger, never a stored balance. About 1 minute.", [
  ("15-bookings-past", "Driver", "Bookings list",
   "Tabs for Upcoming, Active, Past and Cancelled, with the address, times and the amount.",
   "Every past booking is one tap from its receipt, or from Book again."),
  ("16-spending", "Driver", "Spending summary",
   "Spent this month, this year and all time, plus receipts and a CSV statement.",
   "These totals are calculated from the ledger, so they can never drift out of sync."),
 ]),
 ("4. Price negotiation", "A feature the main competitors don't show. About 4 minutes.", [
  ("17-offer-dialog", "Driver", "Make an offer",
   "The driver offers a total price against the listed £6.00. Times are fixed once sent.",
   "Drivers can negotiate. Phone numbers, emails and links are blocked in messages so deals stay on the platform."),
  ("18-offer-auto-declined", "Driver", "Below the host's minimum",
   "A £3.00 offer is declined automatically because the host set a lowest acceptable price.",
   "Hosts set a floor once and never see lowball offers. The driver is told the listed price is still available."),
  ("19-offer-waiting", "Driver", "Offer sent",
   "A valid £4.50 offer is open. It expires in 30 minutes because the stay is starting soon.",
   "Offers expire so nobody waits forever. The slot is not reserved while negotiating."),
  ("20-host-notifications", "Host", "Host is notified",
   "The host's bell lists the new price offer, plus earlier bookings, messages and arrivals.",
   "Push, email and SMS channels are wired in the backend. In the demo they appear in-app."),
  ("21-host-offers", "Host", "Offers inbox",
   "The offer is highlighted as Your turn, next to the earlier declined one.",
   "Hosts see exactly which negotiations are waiting on them."),
  ("22-host-offer-thread", "Host", "Accept, counter or decline",
   "The host sees the driver's £4.50 against the £6.00 list price, and can Accept, Counter or Decline.",
   "Up to three counter-offers are allowed per negotiation, then it closes."),
  ("23-counter-dialog", "Host", "Counter-offer",
   "The host counters with £5.00 and can add a short message.",
   "A counter-offer can't go above the listed price."),
  ("24-counter-sent", "Host", "Counter sent",
   "The history shows both sides: driver £4.50, host £5.00, with timestamps.",
   "Every offer and counter is saved with who, how much and when."),
  ("25-driver-counter", "Driver", "Driver sees the counter",
   "The driver gets the host's £5.00 and can accept, counter or decline.",
   "The same thread, from the driver's side."),
  ("26-accepted-pay", "Driver", "Accepted: pay within 15 minutes",
   "After acceptance the driver has 15 minutes to pay, or the offer lapses.",
   "An accepted offer turns straight into a payable booking at the agreed price."),
  ("27-negotiated-booking", "Driver", "Booked at the negotiated price",
   "A confirmed booking marked Negotiated price (£4.50 instead of £6.00), with the address and the gate code.",
   "The platform's 20% applies to the final agreed price."),
 ]),
 ("5. The host's side", "Dashboard, spaces, availability and payouts. About 4 minutes.", [
  ("28-host-dashboard", "Host", "Host dashboard",
   "Money available to pay out, earned this month, pending (inside the dispute window) and all-time, with upcoming and recent bookings.",
   "Hosts see exactly where their money is. It becomes available after the dispute window passes."),
  ("29-my-spaces", "Host", "My spaces",
   "Each space with its photo, price, bookings, earnings and rating, plus Edit, Availability and a visible-in-search switch.",
   "Pausing a space hides it from search without cancelling existing bookings."),
  ("30-availability", "Host", "Weekly availability",
   "Opening hours per day (UK time), with the option to be open 24/7 and to block specific dates.",
   "Drivers can only book inside these hours, and a booked slot is removed automatically."),
  ("31-add-space-top", "Host", "Add a space",
   "Title, address, space type, vehicle size, photo upload and a pin drop on the map.",
   "A new space goes to the admin approval queue before it appears in search."),
  ("32-add-space-pricing", "Host", "Pricing and booking rules",
   "Hourly and day rates, minimum and maximum stay, buffer between bookings, instant-book or request-to-book, and allow price offers.",
   "Hosts control price, rules and how drivers can book."),
  ("33-earnings", "Host", "Earnings",
   "Available balance, pending, paid out and totals, with CSV statements. Here the balance is -£1.20 because a later refund took back a share of an already paid-out booking.",
   "Refunds reduce the host's earnings in proportion, and the commission is refunded in proportion too."),
  ("34-payout-history", "Host", "Payout history",
   "After tapping Pay out, the full £40.72 shows as Paid out with a dated payout entry.",
   "Payouts are automatic in production (weekly, minimum £10). Here it's on demand."),
 ]),
 ("6. Request-to-book", "For hosts who want to approve each booking. About 3 minutes.", [
  ("35-explore-waterloo", "Driver", "Search another area",
   "Tap an area chip (here Waterloo). The Request tag marks spaces where the host approves each booking.",
   "The map re-centres and shows only spaces free for the whole chosen window."),
  ("36-request-notice", "Driver", "Request to book",
   "The button changes to Request to book, with a note that the card is held, not charged, until the host accepts.",
   "No charge happens unless the host says yes."),
  ("37-awaiting-host", "Driver", "Awaiting host",
   "The booking shows Awaiting host with the card hold, and the driver can withdraw the request.",
   "If the host misses the window, the hold is released automatically and the driver is told."),
  ("38-host-request-card", "Host", "Request lands on the dashboard",
   "The request appears at the top of the host's dashboard with the amount they would earn.",
   "Hosts have 30 minutes, or less if the stay starts sooner."),
  ("39-host-accept", "Host", "Accept or decline",
   "The request shows the commission (20%) and the host's earnings (£9.60 of £12.00). Accept or Decline.",
   "Accepting takes the held payment and confirms the booking. Declining releases the hold."),
  ("40-request-accepted", "Host", "Booking confirmed",
   "The booking is confirmed with the driver's name and the earnings breakdown.",
   "Hosts can still cancel, in which case the driver always gets a full refund and the host is warned."),
 ]),
 ("7. When things go wrong", "The reliability promise. About 2 minutes.", [
  ("41-space-occupied-dialog", "Driver", "Space occupied",
   "Report a problem offers three options: message the host, find a nearby alternative, or get a full refund.",
   "This directly answers the most common complaint about competing apps: arriving to find the space taken."),
  ("42-occupied-refunded", "Driver", "Instant full refund",
   "The booking is cancelled with a full refund, and the report is marked Resolved automatically. The timeline shows the refund.",
   "The host is warned, and repeated cases lead to suspension."),
 ]),
 ("8. Admin", "Running the platform. About 4 minutes.", [
  ("43-admin-overview", "Admin", "Platform overview",
   "Gross booking value, commission earned, today's bookings, parked now, users, listings awaiting approval, open disputes and low-rated users.",
   "A live health check of the marketplace."),
  ("44-admin-approval-queue", "Admin", "Approval queue",
   "A pending space with badges for Host verified and Right-to-let declared, and Approve or Reject.",
   "Every new space is reviewed before drivers can see it."),
  ("45-admin-approved", "Admin", "Approved",
   "The queue is empty and the space is now Live. The host is notified.",
   "Approvals are logged in the audit trail."),
  ("46-admin-bookings", "Admin", "All bookings",
   "Every booking with driver, host, plate, amount and status. The cancelled one shows its refund.",
   "Tap any booking to refund or force-end it."),
  ("47-admin-refund", "Admin", "Issue a refund",
   "A refund form with an amount and a reason shown to the driver.",
   "Commission and host earnings are reduced in proportion, so the accounts always balance."),
  ("48-admin-disputes", "Admin", "Disputes queue",
   "An open dispute (extra not provided) and a resolved one (space occupied).",
   "While a dispute is open, the host's payout for that booking is frozen."),
  ("49-admin-dispute-detail", "Admin", "Dispute evidence",
   "The report, the extra in question, the chat log and the full booking timeline.",
   "Admins decide with all the evidence in one place."),
  ("50-admin-resolve", "Admin", "Resolve the dispute",
   "Choose a refund (capped at the extra's price here) or no refund, add a note, and optionally warn or suspend a user.",
   "Both parties are notified of the decision."),
  ("51-admin-resolved", "Admin", "Resolved",
   "The dispute shows the decision and a £1.50 refund, and the timeline gets a refund entry.",
   "The host's payout is released once the dispute closes."),
  ("52-admin-users", "Admin", "Users",
   "Search users, see verification, bookings and ratings, and suspend, reinstate or verify.",
   "A suspended user's access stops immediately."),
  ("53-admin-settings", "Admin", "Platform settings",
   "Commission rate, dispute window, grace period, overstay fee, response times and minimum payout.",
   "Changing the commission only affects new bookings. Old bookings keep the rate they were made with."),
  ("54-admin-audit", "Admin", "Audit log",
   "Every admin action with who did it, when and the details.",
   "Full accountability for refunds, approvals and setting changes."),
 ]),
 ("9. New user, verification and privacy", "Registering safely. About 3 minutes.", [
  ("55-register", "New user", "Create an account",
   "Name, email and password, an option to also host, and acceptance of the Terms and Privacy Policy.",
   "The terms version and time are stored with the account."),
  ("56-register-filled", "New user", "Ready to register",
   "The form filled in with the terms accepted.",
   "Terms and Privacy are editable by admins, and each edit bumps the version."),
  ("57-verify-email", "New user", "Verify email",
   "A 6-digit code is sent. In demo mode the code is shown on screen because no real email is sent.",
   "Users must verify before they can book or list a space."),
  ("58-email-verified", "New user", "Email verified",
   "The email is confirmed and the phone step opens.",
   "Two checks keep fake accounts out."),
  ("59-phone-code", "New user", "Verify phone",
   "The phone number gets a text-message code. Again the demo shows the code on screen.",
   "SMS delivery plugs into a provider such as Twilio."),
  ("60-all-set", "New user", "All set",
   "Both checks passed.",
   "The account can now book or list."),
  ("61-profile", "New user", "Profile",
   "Vehicles, a Become a host option, and account and privacy links.",
   "Drivers add their vehicles, including electric ones with a connector type."),
  ("62-privacy", "New user", "Privacy and your data (UK GDPR)",
   "Verified status, Terms, Privacy, Help, Download my data and Delete my account.",
   "Users can export everything we hold or delete their account. Financial records are kept as the law requires and the rest is anonymised."),
 ]),
]

ACCOUNTS = [
 ("Driver", "driver@demo.parkspace.test", "Has two vehicles (one electric)"),
 ("Host 1", "host@demo.parkspace.test", "King's Cross, Euston, Bloomsbury, Camden, Islington"),
 ("Host 2", "omar@demo.parkspace.test", "Shoreditch, Waterloo (request-to-book), Canary Wharf (awaiting approval)"),
 ("Admin", "admin@demo.parkspace.test", "Can also switch to Driver mode"),
]

CSS = """
@page { size: A4; margin: 9mm 10mm 9mm 10mm; }
* { box-sizing: border-box; }
body { font-family: -apple-system, "Helvetica Neue", Arial, sans-serif; color: #1b1f2a; font-size: 9.5pt; line-height: 1.45; margin: 0; }
h1,h2,h3 { color: #0f2fa8; line-height: 1.2; margin: 0; }
.cover { background: linear-gradient(135deg, #0f2fa8, #2f6bff); color: white; border-radius: 14px; padding: 30pt 26pt; margin-bottom: 14pt; }
.cover h1 { color: white; font-size: 28pt; margin-bottom: 6pt; }
.cover p { margin: 0; color: #dbe5ff; font-size: 11.5pt; }
.meta { font-size: 8.5pt; color: #5b6275; margin-bottom: 10pt; }
.box { border: 1px solid #e3e6f0; border-radius: 10px; padding: 10pt 12pt; margin: 8pt 0; break-inside: avoid; }
table { width: 100%; border-collapse: collapse; font-size: 9pt; }
th { background: #0f2fa8; color: white; text-align: left; padding: 5pt 7pt; }
td { padding: 5pt 7pt; border-bottom: 1px solid #e3e6f0; vertical-align: top; }
.sec { break-before: page; margin: 0 0 6pt; }
.sec h2 { font-size: 16pt; border-bottom: 2px solid #dde6ff; padding-bottom: 4pt; }
.sec p { margin: 4pt 0 0; color: #5b6275; }
.grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8pt; margin-top: 6pt; }
.step { border: 1px solid #e3e6f0; border-radius: 12px; padding: 7pt; break-inside: avoid; background: #fff; }
.step .top { display: flex; align-items: center; gap: 6pt; margin-bottom: 5pt; }
.num { background: #2350f0; color: #fff; border-radius: 50%; width: 17pt; height: 17pt; min-width: 17pt; display: flex; align-items: center; justify-content: center; font-weight: 700; font-size: 8pt; }
.title { font-weight: 700; font-size: 9pt; line-height: 1.2; }
.who { margin-left: auto; font-size: 7pt; font-weight: 700; padding: 1.5pt 5pt; border-radius: 10px; background: #eef2ff; color: #2350f0; white-space: nowrap; }
.who.Host { background: #e5f6ec; color: #136c37; } .who.Admin { background: #ffeede; color: #b34700; } .who.New { background: #f0e8ff; color: #6b33c9; }
.shot { display: block; width: 100%; max-width: 35mm; margin: 0 auto 5pt; border-radius: 10px; border: 1px solid #d8dcea; box-shadow: 0 3px 10px rgba(20,30,80,.15); }
.lbl { font-size: 7pt; font-weight: 700; text-transform: uppercase; letter-spacing: .04em; color: #7a8196; margin: 3pt 0 1pt; }
.txt { font-size: 7.8pt; margin: 0; line-height: 1.38; }
.say { background: #f1f5ff; border-left: 3px solid #2350f0; padding: 3pt 5pt; border-radius: 4px; font-size: 7.8pt; line-height: 1.38; margin: 0; }
.small { font-size: 8pt; color: #5b6275; }
ol { margin: 4pt 0 0; padding-left: 14pt; } li { margin-bottom: 2pt; }
"""

def esc(s): return html.escape(s, quote=True)

def build():
    out = [f"<!doctype html><html lang='en-GB'><head><meta charset='utf-8'><title>ParkSpace Demo Guide</title><style>{CSS}</style></head><body>"]
    out.append("<div class='cover'><h1>ParkSpace: Demo Guide</h1><p>Every flow, screen by screen, with what you're seeing and what to say.</p></div>")
    out.append("<div class='meta'>Proof-of-concept build · captured on a phone-sized screen · UK launch market (GBP) · Working name: ParkSpace (placeholder brand)</div>")
    out.append("<div class='box'><h3>How to use this guide</h3><p class='txt'>The demo follows nine short flows, about 25 minutes in total, or pick the ones that matter to your audience. Each card shows the screen, <b>what you are seeing</b>, and a suggested line to <b>say</b>. The coloured tag shows who is logged in: Driver, Host or Admin.</p></div>")
    out.append("<div class='box'><h3>Before you start</h3><ol>"
               "<li>Open the app: <b>https://saeedmurrad.github.io/driveway-parking-app/</b></li>"
               "<li>Wake the backend about a minute earlier by opening <b>https://parkspace-api.onrender.com/health</b>. The free hosting tier sleeps when idle.</li>"
               "<li>Use two browser windows (one normal, one private) so you can be the driver and the host at the same time.</li>"
               "<li>Use the demo role buttons on the login screen, or the accounts below. Password for all: <b>demo1234</b>.</li></ol></div>")
    out.append("<table><tr><th>Role</th><th>Login</th><th>Notes</th></tr>" + "".join(f"<tr><td><b>{a}</b></td><td>{b}</td><td>{c}</td></tr>" for a,b,c in ACCOUNTS) + "</table>")
    out.append("<div class='box'><h3>Good to know</h3><ul class='txt'>"
               "<li>Payments are <b>simulated</b>, and email, SMS and push messages are shown in-app. Demo mode shows verification codes on screen.</li>"
               "<li>The dispute window is set to <b>2 minutes</b> so host payouts can be shown live. The spec's default is 24 hours.</li>"
               "<li>On a free tier the first load after a quiet spell can take about a minute.</li></ul></div>")
    n = 0
    for title, blurb, steps in SECTIONS:
        out.append(f"<div class='sec'><h2>{esc(title)}</h2><p>{esc(blurb)}</p></div><div class='grid'>")
        for img, who, t, what, say in steps:
            n += 1
            cls = who.split()[0]
            out.append(
                f"<div class='step'><div class='top'><div class='num'>{n}</div><div class='title'>{esc(t)}</div><div class='who {esc(cls)}'>{esc(who)}</div></div>"
                f"<img class='shot' src='demo-screenshots/{img}.jpg' alt='{esc(t)}'>"
                f"<div class='lbl'>What you see</div><p class='txt'>{esc(what)}</p>"
                f"<div class='lbl'>Say</div><p class='say'>{esc(say)}</p></div>")
        out.append("</div>")
    out.append("<div class='sec'><h2>Wrap-up talking points</h2></div><div class='box'><ul class='txt'>"
               "<li><b>Reliability first:</b> the instant refund when a space is blocked, host-cancellation refunds and a disputes desk answer the biggest complaints about competing apps.</li>"
               "<li><b>Beyond booking:</b> price negotiation, paid extras (including EV charging matched to the car), request-to-book and overstay handling are built and working.</li>"
               "<li><b>Money you can trust:</b> every total comes from a payment ledger, the commission rate is stored per booking, and every admin action is logged.</li>"
               "<li><b>Decision for stakeholders:</b> the planned 20% host commission is higher than JustPark's reported host fee. See the competitor analysis for options.</li>"
               "<li><b>Next steps:</b> real Stripe payments, real email/SMS/push, insurance and legal terms, and a launch-area supply plan.</li></ul></div>")
    out.append("</body></html>")
    path = os.path.join(HERE, "demo-guide.html")
    open(path, "w").write("\n".join(out))
    print("wrote", path, "|", n, "steps")

if __name__ == "__main__":
    build()
