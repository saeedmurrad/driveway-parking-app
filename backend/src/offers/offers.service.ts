import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { DbService } from '../db/db.service';
import { SettingsService } from '../settings/settings.service';
import { NotificationsService } from '../notifications/notifications.service';
import { BookingsService } from '../bookings/bookings.service';
import { calculatePrice } from '../bookings/pricing';
import { containsContactInfo } from './contact-filter';

const r2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;
const MAX_ROUND = 4; // 1 offer + 3 counter-offers
const SAFETY = 'For your safety, keep phone numbers, emails and links out of messages. Negotiate inside ParkSpace.';

@Injectable()
export class OffersService {
  constructor(
    private readonly db: DbService,
    private readonly settings: SettingsService,
    private readonly notes: NotificationsService,
    private readonly bookings: BookingsService,
  ) {}

  private expiry(start: Date) {
    // 2 hours normally, 30 minutes when the stay starts within 3 hours
    const soon = start.getTime() - Date.now() < 3 * 3_600_000;
    return new Date(Date.now() + (soon ? 30 : 120) * 60_000);
  }

  private async slotFree(listingId: string, start: Date, end: Date, buffer: number) {
    const r = await this.db.query(
      `select listing_available($1,$2,$3) as open,
              not exists (select 1 from bookings where listing_id = $1
                and status in ('pending_payment','requested','confirmed','parked','overstay')
                and tstzrange(booked_start, blocked_end) && tstzrange($2, $3 + make_interval(mins => $4))) as free`,
      [listingId, start, end, buffer]);
    return r.rows[0].open && r.rows[0].free;
  }

  async create(driverId: string, d: { listingId: string; vehicleId?: string; start: string; end: string; amount: number; message?: string; extras?: { id: string; quantity?: number }[] }) {
    const start = new Date(d.start), end = new Date(d.end);
    if (!(end > start) || start.getTime() < Date.now() - 10 * 60_000) throw new BadRequestException('Invalid stay times');
    if (d.message && containsContactInfo(d.message)) throw new BadRequestException(SAFETY);
    const l = (await this.db.query(
      `select id, title, host_id, allow_offers, min_offer_price, buffer_minutes, price_hour, price_day
       from listings where id = $1 and status = 'live'`, [d.listingId])).rows[0];
    if (!l) throw new NotFoundException('Listing not available');
    if (!l.allow_offers) throw new BadRequestException('This host does not accept offers');
    if (l.host_id === driverId) throw new BadRequestException('You cannot make an offer on your own space');
    if (!(await this.slotFree(l.id, start, end, l.buffer_minutes))) throw new ConflictException('That time is no longer available');

    const quote = await this.bookings.quote(l.id, start, end, d.extras, d.vehicleId);
    const amount = r2(d.amount);
    if (!(amount > 0)) throw new BadRequestException('Enter an offer amount');
    if (amount >= quote.total) throw new BadRequestException(`Your offer is at or above the listed price (£${quote.total.toFixed(2)}). Just book it!`);

    const hours = Math.ceil((end.getTime() - start.getTime()) / 3_600_000);
    const id = randomUUID();
    const belowMin = l.min_offer_price != null && amount / hours < Number(l.min_offer_price);
    const offer = (await this.db.query(
      `insert into offers (id, thread_id, listing_id, driver_id, vehicle_id, start_at, end_at, amount, round, sent_by, status, expires_at, message, decline_reason, extras)
       values ($1,$1,$2,$3,$4,$5,$6,$7,1,'driver',$8,$9,$10,$11,$12) returning *`,
      [id, l.id, driverId, d.vehicleId ?? null, start, end, amount, belowMin ? 'declined' : 'open',
       this.expiry(start), d.message ?? null, belowMin ? 'below_minimum' : null, d.extras?.length ? JSON.stringify(d.extras) : null])).rows[0];

    if (belowMin) {
      await this.notes.notify(driverId, 'offer_declined', 'Offer declined',
        `Thanks for your offer on ${l.title}. It is lower than the host can accept, but the listed price of £${quote.total.toFixed(2)} is still available.`, { ref: ['offer', id] });
    } else {
      await this.notes.notify(l.host_id, 'offer_received', 'New price offer',
        `£${amount.toFixed(2)} offered for ${l.title} (listed £${quote.total.toFixed(2)}).`, { ref: ['offer', id] });
    }
    return { offer, autoDeclined: belowMin, listedTotal: quote.total };
  }

  private async load(offerId: string) {
    const o = (await this.db.query(
      `select o.*, l.title, l.host_id, l.buffer_minutes, l.price_hour, l.price_day
       from offers o join listings l on l.id = o.listing_id where o.id = $1`, [offerId])).rows[0];
    if (!o) throw new NotFoundException();
    return o;
  }

  private quoteFor(o: any) {
    return this.bookings.quote(o.listing_id, new Date(o.start_at), new Date(o.end_at), o.extras ?? undefined, o.vehicle_id);
  }

  async respond(userId: string, offerId: string, action: 'accept' | 'decline' | 'counter', amount?: number, message?: string) {
    const o = await this.load(offerId);
    const role = o.host_id === userId ? 'host' : o.driver_id === userId ? 'driver' : null;
    if (!role) throw new NotFoundException();
    if (o.sent_by === role) throw new ForbiddenException('Waiting for the other side to respond');
    if (o.status !== 'open') throw new BadRequestException('This offer is no longer open');
    if (new Date(o.expires_at) < new Date()) {
      await this.db.query(`update offers set status = 'expired' where id = $1`, [offerId]);
      throw new BadRequestException('This offer has expired');
    }
    if (message && containsContactInfo(message)) throw new BadRequestException(SAFETY);
    const other = role === 'host' ? o.driver_id : o.host_id;
    const ref: [string, string] = ['offer', o.thread_id];

    if (action === 'decline') {
      await this.db.query(`update offers set status = 'declined' where id = $1`, [offerId]);
      await this.notes.notify(other, 'offer_declined', 'Offer declined', `${role === 'host' ? 'The host' : 'The driver'} declined the offer on ${o.title}.`, { ref });
      return this.thread(userId, o.thread_id);
    }

    if (action === 'accept') {
      if (!(await this.slotFree(o.listing_id, new Date(o.start_at), new Date(o.end_at), o.buffer_minutes))) {
        await this.db.query(`update offers set status = 'expired' where id = $1`, [offerId]);
        throw new ConflictException('Sorry, that time has just been booked by someone else');
      }
      await this.db.query(`update offers set status = 'accepted', pay_by = now() + interval '15 minutes' where id = $1`, [offerId]);
      await this.notes.notify(o.driver_id, 'offer_accepted',
        role === 'host' ? 'Offer accepted!' : 'You accepted the counter-offer',
        `£${Number(o.amount).toFixed(2)} for ${o.title}. Pay within 15 minutes to confirm the booking.`, { ref });
      if (role === 'driver') await this.notes.notify(o.host_id, 'offer_accepted', 'Counter-offer accepted', `The driver accepted £${Number(o.amount).toFixed(2)} for ${o.title} and has 15 minutes to pay.`, { ref });
      return this.thread(userId, o.thread_id);
    }

    // counter
    if (o.round >= MAX_ROUND) throw new BadRequestException('The maximum of 3 counter-offers has been reached. You can only accept or decline.');
    const q = await this.quoteFor(o);
    const a = r2(Number(amount));
    if (!(a > 0)) throw new BadRequestException('Enter a counter amount');
    if (a >= q.total && role === 'driver') throw new BadRequestException(`That is at or above the listed price (£${q.total.toFixed(2)}).`);
    if (a > q.total) throw new BadRequestException(`A counter-offer cannot be above the listed price (£${q.total.toFixed(2)}).`);
    await this.db.tx(async (c) => {
      await c.query(`update offers set status = 'countered' where id = $1`, [offerId]);
      await c.query(
        `insert into offers (thread_id, listing_id, driver_id, vehicle_id, start_at, end_at, amount, round, sent_by, parent_offer_id, status, expires_at, message)
         values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,'open',$11,$12)`,
        [o.thread_id, o.listing_id, o.driver_id, o.vehicle_id, o.start_at, o.end_at, a, o.round + 1, role, offerId, this.expiry(new Date(o.start_at)), message ?? null]);
    });
    await this.notes.notify(other, 'offer_countered', 'Counter-offer',
      `${role === 'host' ? 'The host' : 'The driver'} countered with £${a.toFixed(2)} for ${o.title}${o.round + 1 >= MAX_ROUND ? ' (final round)' : ''}.`, { ref });
    return this.thread(userId, o.thread_id);
  }

  /** Accepted offer -> payable booking at the agreed price. */
  async pay(driverId: string, offerId: string) {
    const o = await this.load(offerId);
    if (o.driver_id !== driverId) throw new NotFoundException();
    if (o.status !== 'accepted') throw new BadRequestException('This offer is not ready to pay');
    if (new Date(o.pay_by) < new Date()) {
      await this.db.query(`update offers set status = 'expired' where id = $1`, [offerId]);
      throw new BadRequestException('The 15 minutes to pay have passed, so the offer has expired.');
    }
    const created = await this.bookings.create(driverId, {
      listingId: o.listing_id, vehicleId: o.vehicle_id ?? undefined,
      start: new Date(o.start_at).toISOString(), end: new Date(o.end_at).toISOString(), extras: o.extras ?? undefined,
    }, { offerId, amount: Number(o.amount) });
    const booking = await this.bookings.pay(driverId, created.booking.id, true);
    await this.db.query(`update offers set status = 'paid' where id = $1`, [offerId]);
    return booking;
  }

  async mine(userId: string) {
    const { rows } = await this.db.query(
      `select distinct on (o.thread_id) o.*, l.title, l.host_id, l.price_hour, l.price_day,
              split_part(du.name,' ',1) as driver_name, split_part(hu.name,' ',1) as host_name,
              (select count(*) from offers x where x.thread_id = o.thread_id)::int as steps
       from offers o join listings l on l.id = o.listing_id
       join users du on du.id = o.driver_id join users hu on hu.id = l.host_id
       where o.driver_id = $1 or l.host_id = $1
       order by o.thread_id, o.round desc`, [userId]);
    const out = [];
    for (const o of rows) {
      const role = o.host_id === userId ? 'host' : 'driver';
      const live = o.status === 'open' || o.status === 'accepted';
      const expired = (o.status === 'open' && new Date(o.expires_at) < new Date()) || (o.status === 'accepted' && new Date(o.pay_by) < new Date());
      const status = expired ? 'expired' : o.status;
      out.push({
        ...o, status, role, listed_total: (await this.quoteFor(o)).total,
        awaiting_me: !expired && ((o.status === 'open' && o.sent_by !== role) || (o.status === 'accepted' && role === 'driver')),
        live: live && !expired,
      });
    }
    return out.sort((a, b) => Number(b.awaiting_me) - Number(a.awaiting_me) || +new Date(b.created_at) - +new Date(a.created_at));
  }

  async thread(userId: string, threadId: string) {
    const { rows } = await this.db.query(
      `select o.*, l.title, l.host_id, l.price_hour, l.price_day, split_part(du.name,' ',1) as driver_name, split_part(hu.name,' ',1) as host_name
       from offers o join listings l on l.id = o.listing_id
       join users du on du.id = o.driver_id join users hu on hu.id = l.host_id
       where o.thread_id = $1 order by o.round`, [threadId]);
    if (!rows.length || (rows[0].driver_id !== userId && rows[0].host_id !== userId)) throw new NotFoundException();
    const last = rows[rows.length - 1];
    const role = rows[0].host_id === userId ? 'host' : 'driver';
    const q = await this.quoteFor(last);
    const expired = (last.status === 'open' && new Date(last.expires_at) < new Date()) || (last.status === 'accepted' && new Date(last.pay_by) < new Date());
    return {
      role, listing_id: last.listing_id, title: last.title, listed_total: q.total, extras: q.extras,
      start_at: last.start_at, end_at: last.end_at, driver_name: last.driver_name, host_name: last.host_name,
      current: { ...last, status: expired ? 'expired' : last.status },
      can_respond: !expired && last.status === 'open' && last.sent_by !== role,
      can_pay: !expired && last.status === 'accepted' && role === 'driver',
      can_counter: last.round < MAX_ROUND,
      steps: rows.map((r) => ({ id: r.id, round: r.round, sent_by: r.sent_by, amount: r.amount, message: r.message, status: r.status, decline_reason: r.decline_reason, created_at: r.created_at })),
    };
  }
}
