import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { PoolClient } from 'pg';
import { randomBytes } from 'crypto';
import { DbService } from '../db/db.service';
import { SettingsService } from '../settings/settings.service';
import { calculatePrice } from './pricing';
import { refundPercent } from './policy';
import { NotificationsService } from '../notifications/notifications.service';

const fmt = (d: Date | string) => new Date(d).toLocaleString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', timeZone: 'Europe/London' });
const r2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;
const PAID = ['confirmed', 'parked', 'overstay', 'completed'];

@Injectable()
export class BookingsService {
  constructor(
    private readonly db: DbService,
    private readonly settings: SettingsService,
    private readonly notes: NotificationsService,
  ) {}

  async quote(listingId: string, start: Date, end: Date) {
    const { rows } = await this.db.query('select price_hour, price_day from listings where id = $1', [listingId]);
    if (!rows[0]) throw new NotFoundException();
    const rate = await this.settings.getNumber('commission_rate');
    return calculatePrice({
      start, end, priceHour: Number(rows[0].price_hour),
      priceDay: rows[0].price_day == null ? null : Number(rows[0].price_day), commissionRate: rate,
    });
  }

  async create(driverId: string, dto: { listingId: string; vehicleId?: string; start: string; end: string }) {
    const start = new Date(dto.start);
    const end = new Date(dto.end);
    if (!(end > start)) throw new BadRequestException('End must be after start');
    if (start.getTime() < Date.now() - 10 * 60_000) throw new BadRequestException('Start time is in the past');
    const rate = await this.settings.getNumber('commission_rate');

    return this.db.tx(async (c) => {
      const l = (await c.query(
        `select host_id, price_hour, price_day, buffer_minutes, min_stay_minutes, max_stay_minutes,
                listing_available(id, $2, $3) as open
         from listings where id = $1 and status = 'live'`,
        [dto.listingId, start, end])).rows[0];
      if (!l) throw new NotFoundException('Listing not available');
      if (l.host_id === driverId) throw new BadRequestException('You cannot book your own space');
      if (!l.open) throw new BadRequestException('The host is not offering this space at those times');
      const mins = (end.getTime() - start.getTime()) / 60_000;
      if (mins < l.min_stay_minutes) throw new BadRequestException(`Minimum stay is ${l.min_stay_minutes} minutes`);
      if (mins > l.max_stay_minutes) throw new BadRequestException(`Maximum stay is ${Math.round(l.max_stay_minutes / 60)} hours`);

      const price = calculatePrice({
        start, end, priceHour: Number(l.price_hour),
        priceDay: l.price_day == null ? null : Number(l.price_day), commissionRate: rate,
      });
      const blockedEnd = new Date(end.getTime() + l.buffer_minutes * 60_000);
      const reference = 'PS-' + randomBytes(3).toString('hex').toUpperCase();
      try {
        // The exclusion constraint `no_double_booking` rejects overlaps atomically.
        const { rows } = await c.query(
          `insert into bookings (reference, listing_id, driver_id, host_id, vehicle_id, booked_start, booked_end,
             blocked_end, parking_amount, extras_amount, total_amount, commission_rate, commission_amount,
             host_earnings, status)
           values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,'pending_payment') returning *`,
          [reference, dto.listingId, driverId, l.host_id, dto.vehicleId ?? null, start, end, blockedEnd,
           price.parking, price.extras, price.total, price.commissionRate, price.commission, price.hostEarnings]);
        await this.event(c, rows[0].id, 'created', 'driver', driverId);
        return { booking: rows[0], price };
      } catch (e: any) {
        if (e.code === '23P01') throw new ConflictException('That time slot has just been taken');
        throw e;
      }
    });
  }

  /**
   * Simulated payment. In production this is a Stripe PaymentIntent confirmed client-side;
   * the booking is confirmed only from the Stripe webhook. The ledger writes are identical.
   */
  async pay(driverId: string, id: string) {
    return this.db.tx(async (c) => {
      const cur = (await c.query(
        `select b.*, l.booking_mode, l.title from bookings b join listings l on l.id = b.listing_id
         where b.id = $1 and b.driver_id = $2 and b.status = 'pending_payment' for update of b`, [id, driverId])).rows[0];
      if (!cur) throw new BadRequestException('Booking is not awaiting payment (it may have expired)');
      const ref: [string, string] = ['booking', id];
      const pi = 'mock_pi_' + randomBytes(6).toString('hex');

      if (cur.booking_mode === 'request') {
        // Card is authorised (held), not charged. The host has a limited time to answer.
        const mins = await this.settings.getNumber('request_response_minutes');
        const respondBy = new Date(Math.min(Date.now() + mins * 60_000, new Date(cur.booked_start).getTime()));
        await c.query(`update bookings set status = 'requested', stripe_payment_intent = $2, respond_by = $3 where id = $1`, [id, pi, respondBy]);
        await this.event(c, id, 'requested', 'driver', driverId);
        await this.notes.notify(cur.host_id, 'booking_request', 'New booking request',
          `${cur.title} · ${fmt(cur.booked_start)}. Accept within ${Math.max(1, Math.round((respondBy.getTime() - Date.now()) / 60_000))} minutes.`, { ref, channels: ['push'], client: c });
        await this.notes.notify(driverId, 'booking_request', 'Request sent',
          `Your card is on hold. ${cur.title} will confirm once the host accepts.`, { ref, client: c });
        return this.detail(driverId, id, c);
      }

      await c.query(`update bookings set status = 'confirmed', stripe_payment_intent = $2 where id = $1`, [id, pi]);
      await this.capture(c, cur, pi);
      return this.detail(driverId, id, c);
    });
  }

  /** Takes the money (ledger charge), confirms and notifies. Used by instant pay and by host acceptance. */
  private async capture(c: PoolClient, b: any, pi: string) {
    await c.query(
      `insert into transactions (booking_id, user_id, type, amount, provider_ref) values ($1,$2,'charge',$3,$4)`,
      [b.id, b.driver_id, b.total_amount, pi]);
    await this.event(c, b.id, 'paid', 'driver', b.driver_id);
    await this.event(c, b.id, 'confirmed', 'system');
    const t = (await c.query('select title from listings where id = $1', [b.listing_id])).rows[0].title;
    const ref: [string, string] = ['booking', b.id];
    await this.notes.notify(b.driver_id, 'booking_confirmed', 'Booking confirmed',
      `${t} · ${fmt(b.booked_start)}. Your address and access instructions are ready.`, { ref, channels: ['push', 'email'], client: c });
    await this.notes.notify(b.host_id, 'booking_confirmed', 'New booking',
      `${t} · ${fmt(b.booked_start)} · you earn £${Number(b.host_earnings).toFixed(2)}.`, { ref, channels: ['push', 'email'], client: c });
  }

  /** Host answers a request-to-book. Accept captures the held card; decline releases it. */
  async respond(hostId: string, id: string, accept: boolean) {
    return this.db.tx(async (c) => {
      const b = (await c.query(
        `select * from bookings where id = $1 and host_id = $2 and status = 'requested' for update`, [id, hostId])).rows[0];
      if (!b) throw new BadRequestException('This request is no longer open');
      if (b.respond_by && new Date(b.respond_by) < new Date()) throw new BadRequestException('The response time has passed');
      const ref: [string, string] = ['booking', id];
      if (accept) {
        await c.query(`update bookings set status = 'confirmed' where id = $1`, [id]);
        await this.event(c, id, 'accepted', 'host', hostId);
        await this.capture(c, b, b.stripe_payment_intent);
      } else {
        await c.query(`update bookings set status = 'cancelled', cancelled_by = 'host', cancel_reason = 'declined' where id = $1`, [id]);
        await this.event(c, id, 'declined', 'host', hostId);
        await this.notes.notify(b.driver_id, 'booking_declined', 'Request declined',
          `The host declined booking ${b.reference}. Your card hold has been released, so you were not charged.`, { ref, channels: ['push', 'email'], client: c });
      }
      return this.detail(hostId, id, c);
    });
  }

  /** Extend the end time while the booking is active. Charged straight away at the hourly rate. */
  async extend(driverId: string, id: string, hours: number) {
    return this.db.tx(async (c) => {
      const b = (await c.query(
        `select b.*, l.price_hour, l.max_stay_minutes from bookings b join listings l on l.id = b.listing_id
         where b.id = $1 and b.driver_id = $2 and b.status in ('confirmed','parked') and b.booked_end > now() for update of b`,
        [id, driverId])).rows[0];
      if (!b) throw new BadRequestException('You can only extend a booking that has not ended yet');
      const newEnd = new Date(new Date(b.booked_end).getTime() + hours * 3_600_000);
      if ((newEnd.getTime() - new Date(b.booked_start).getTime()) / 60_000 > b.max_stay_minutes) throw new BadRequestException('That goes over this space\'s maximum stay');
      const open = (await c.query('select listing_available($1,$2,$3) as ok', [b.listing_id, b.booked_end, newEnd])).rows[0].ok;
      if (!open) throw new ConflictException('The host is not offering the space for that extra time');
      const extra = r2(hours * Number(b.price_hour));
      const total = r2(Number(b.total_amount) + extra);
      const commission = r2(total * Number(b.commission_rate));
      const buffer = (await c.query('select buffer_minutes from listings where id = $1', [b.listing_id])).rows[0].buffer_minutes;
      try {
        await c.query(
          `update bookings set booked_end = $2, blocked_end = $3, parking_amount = parking_amount + $4, total_amount = $5,
             commission_amount = $6, host_earnings = $7 where id = $1`,
          [id, newEnd, new Date(newEnd.getTime() + buffer * 60_000), extra, total, commission, r2(total - commission)]);
      } catch (e: any) {
        if (e.code === '23P01') throw new ConflictException('Sorry, the space is booked right after yours');
        throw e;
      }
      await c.query(`insert into transactions (booking_id, user_id, type, amount, provider_ref) values ($1,$2,'charge',$3,$4)`,
        [id, driverId, extra, 'mock_ext_' + randomBytes(4).toString('hex')]);
      await this.event(c, id, 'extended', 'driver', driverId);
      await this.notes.notify(b.host_id, 'booking_extended', 'Booking extended',
        `Booking ${b.reference} now ends ${fmt(newEnd)} (+£${extra.toFixed(2)}).`, { ref: ['booking', id], client: c });
      return this.detail(driverId, id, c);
    });
  }

  /** Host answers the "is the car still there?" prompt after the grace period. */
  async carStatus(hostId: string, id: string, stillThere: boolean) {
    return this.db.tx(async (c) => {
      const b = (await c.query(
        `select * from bookings where id = $1 and host_id = $2 and status = 'parked' and overstay_check = 'asked' for update`,
        [id, hostId])).rows[0];
      if (!b) throw new BadRequestException('Nothing to confirm for this booking');
      const ref: [string, string] = ['booking', id];
      if (!stillThere) {
        await c.query(`update bookings set overstay_check = 'gone' where id = $1`, [id]);
        await this.complete(c, { ...b, overstay_check: 'gone' }, 'system', null, 'auto_ended', true);
      } else {
        await c.query(`update bookings set status = 'overstay', overstay_check = 'still_there' where id = $1`, [id]);
        await this.event(c, id, 'overstay', 'host', hostId);
        await this.notes.notify(b.driver_id, 'overstay', 'Overstay: fees now apply',
          `Your car is still at the space after booking ${b.reference} ended. An overstay fee is charged per extra hour until you tap End Booking.`,
          { ref, channels: ['push', 'sms'], client: c });
      }
      return this.detail(hostId, id, c);
    });
  }

  async markParked(userId: string, id: string, geo?: { latitude?: number; longitude?: number }) {
    return this.db.tx(async (c) => {
      const { rows } = await c.query(
        `update bookings set status = 'parked', actual_parked_at = now()
         where id = $1 and driver_id = $2 and status = 'confirmed'
           and now() >= booked_start - interval '15 minutes' and now() <= booked_end returning id`, [id, userId]);
      if (!rows[0]) throw new BadRequestException("You can tap I've Parked from 15 minutes before the start until the end");
      await this.event(c, id, 'parked', 'driver', userId, geo);
      const b = (await c.query('select host_id, reference from bookings where id = $1', [id])).rows[0];
      await this.notes.notify(b.host_id, 'parked', 'Car has arrived', `Booking ${b.reference}: the driver has parked.`, { ref: ['booking', id], client: c });
      return this.detail(userId, id, c);
    });
  }

  async end(userId: string, id: string) {
    return this.db.tx(async (c) => {
      const b = (await c.query(`select * from bookings where id = $1 and driver_id = $2 and status in ('parked','overstay') for update`, [id, userId])).rows[0];
      if (!b) throw new BadRequestException('Booking is not active');
      await this.complete(c, b, 'driver', userId, 'ended');
      return this.detail(userId, id, c);
    });
  }

  /** Completing a booking posts the commission + host earning to the ledger (plus any overstay fee). */
  async complete(c: PoolClient, b: any, actor: 'driver' | 'system', actorId: string | null, event: string, atBookedEnd = false) {
    await c.query(`update bookings set status = 'completed', actual_ended_at = case when $2 then booked_end else now() end where id = $1`, [b.id, atBookedEnd]);
    await c.query(
      `insert into transactions (booking_id, user_id, type, amount) values ($1,null,'commission',$2), ($1,$3,'host_earning',$4)`,
      [b.id, b.commission_amount, b.host_id, b.host_earnings]);
    await this.event(c, b.id, event, actor, actorId);
    const ref: [string, string] = ['booking', b.id];
    const why = event === 'auto_ended' ? 'was ended automatically' : 'has ended';
    let extra = '';
    if (b.status === 'overstay') {
      // Overstay: per extra hour started, at multiplier x hourly rate; host gets the same share as normal bookings.
      const l = (await c.query('select price_hour from listings where id = $1', [b.listing_id])).rows[0];
      const mult = await this.settings.getNumber('overstay_multiplier');
      const hours = Math.max(1, Math.ceil((Date.now() - new Date(b.booked_end).getTime()) / 3_600_000));
      const fee = r2(hours * Number(l.price_hour) * mult);
      const commission = r2(fee * Number(b.commission_rate));
      await c.query(
        `insert into transactions (booking_id, user_id, type, amount) values ($1,$2,'overstay_fee',$3), ($1,null,'commission',$4), ($1,$5,'host_earning',$6)`,
        [b.id, b.driver_id, fee, commission, b.host_id, r2(fee - commission)]);
      await c.query('update bookings set overstay_fee = $2 where id = $1', [b.id, fee]);
      extra = ` An overstay fee of £${fee.toFixed(2)} (${hours}h) was charged.`;
    }
    await this.notes.notify(b.driver_id, 'booking_ended', 'Booking ended', `Booking ${b.reference} ${why}.${extra} Please rate your stay.`, { ref, client: c });
    await this.notes.notify(b.host_id, 'booking_ended', 'Booking ended', `Booking ${b.reference} ${why}. You earned £${Number(b.host_earnings).toFixed(2)}.${extra ? ' Plus overstay fee income.' : ''}`, { ref, client: c });
  }

  async cancel(userId: string, id: string) {
    return this.db.tx(async (c) => {
      const b = (await c.query(
        `select b.*, l.cancellation_policy from bookings b join listings l on l.id = b.listing_id
         where b.id = $1 and (b.driver_id = $2 or b.host_id = $2) for update of b`, [id, userId])).rows[0];
      if (!b) throw new NotFoundException();
      const byHost = b.host_id === userId;
      if (b.status === 'pending_payment' || (b.status === 'requested' && !byHost)) {
        await c.query(`update bookings set status = 'cancelled', cancelled_by = 'driver', cancel_reason = $2 where id = $1`,
          [id, b.status === 'requested' ? 'request withdrawn' : 'abandoned']);
        await this.event(c, id, 'cancelled', 'driver', userId);
        return this.detail(userId, id, c);
      }
      if (b.status !== 'confirmed') throw new BadRequestException('Only confirmed bookings can be cancelled');
      const pct = byHost ? 100 : refundPercent(b.cancellation_policy, b.booked_start, b.created_at);
      const refund = r2((Number(b.total_amount) * pct) / 100);
      const kept = r2(Number(b.total_amount) - refund);
      await c.query(`update bookings set status = 'cancelled', cancelled_by = $2, cancel_reason = $3 where id = $1`,
        [id, byHost ? 'host' : 'driver', `${pct}% refund`]);
      if (refund > 0) {
        await c.query(`insert into transactions (booking_id, user_id, type, amount) values ($1,$2,'refund',$3)`, [id, b.driver_id, refund]);
      }
      if (kept > 0) {
        // Commission is refunded in proportion: the platform only keeps its share of what was retained.
        const commission = r2(kept * Number(b.commission_rate));
        await c.query(
          `insert into transactions (booking_id, user_id, type, amount) values ($1,null,'commission',$2), ($1,$3,'host_earning',$4)`,
          [id, commission, b.host_id, r2(kept - commission)]);
      }
      await this.event(c, id, 'cancelled', byHost ? 'host' : 'driver', userId);
      if (refund > 0) await this.event(c, id, 'refunded', 'system');
      const ref: [string, string] = ['booking', id];
      const other = byHost ? b.driver_id : b.host_id;
      await this.notes.notify(other, 'booking_cancelled', 'Booking cancelled',
        `Booking ${b.reference} was cancelled by the ${byHost ? 'host' : 'driver'}.`, { ref, channels: ['push', 'email'], client: c });
      if (refund > 0) await this.notes.notify(b.driver_id, 'refund', 'Refund issued', `£${refund.toFixed(2)} refunded for booking ${b.reference}.`, { ref, channels: ['push', 'email'], client: c });
      return this.detail(userId, id, c);
    });
  }

  async review(userId: string, id: string, stars: number, comment?: string) {
    return this.db.tx(async (c) => {
      const b = (await c.query(`select * from bookings where id = $1 and status = 'completed' and (driver_id = $2 or host_id = $2)`, [id, userId])).rows[0];
      if (!b) throw new BadRequestException('You can review after a booking is completed');
      const to = b.driver_id === userId ? b.host_id : b.driver_id;
      const dup = await c.query('select 1 from reviews where booking_id = $1 and from_user_id = $2', [id, userId]);
      if (dup.rowCount) throw new ConflictException('You already reviewed this booking');
      await c.query(`insert into reviews (booking_id, from_user_id, to_user_id, listing_id, stars, comment) values ($1,$2,$3,$4,$5,$6)`,
        [id, userId, to, b.driver_id === userId ? b.listing_id : null, stars, comment ?? null]);
      if (b.driver_id === userId) {
        await c.query(`update listings set rating = (select round(avg(stars)::numeric, 2) from reviews where listing_id = $1) where id = $1`, [b.listing_id]);
      }
      return { ok: true };
    });
  }

  /** Booking with listing info. The exact address is only released once the booking is paid. */
  async detail(userId: string, id: string, c?: PoolClient) {
    const q = (t: string, p: unknown[]) => (c ? c.query(t, p) : this.db.query(t, p));
    const b = (await q(
      `select b.*, l.title, l.latitude, l.longitude, l.cancellation_policy, l.address, l.access_instructions,
              du.name as driver_name, hu.name as host_name, v.plate, v.make, v.model
       from bookings b join listings l on l.id = b.listing_id
       join users du on du.id = b.driver_id join users hu on hu.id = b.host_id
       left join vehicles v on v.id = b.vehicle_id
       where b.id = $1 and (b.driver_id = $2 or b.host_id = $2 or exists (select 1 from users where id = $2 and is_admin))`,
      [id, userId])).rows[0];
    if (!b) throw new NotFoundException();
    const isDriver = b.driver_id === userId;
    const paid = PAID.includes(b.status);
    if (isDriver && !paid) { b.address = null; b.access_instructions = null; }
    b.host_name = String(b.host_name).split(' ')[0];
    if (!isDriver) b.driver_name = String(b.driver_name).split(' ')[0];
    b.events = (await q('select event, actor, created_at from booking_events where booking_id = $1 order by created_at', [id])).rows;
    b.reviewed = (await q('select 1 from reviews where booking_id = $1 and from_user_id = $2', [id, userId])).rowCount! > 0;
    if (b.status === 'confirmed') {
      const pct = b.host_id === userId ? 100 : refundPercent(b.cancellation_policy, b.booked_start, b.created_at);
      b.cancel_quote = { percent: pct, amount: r2((Number(b.total_amount) * pct) / 100) };
    }
    if (b.status === 'overstay') {
      const mult = await this.settings.getNumber('overstay_multiplier');
      const hours = Math.max(1, Math.ceil((Date.now() - new Date(b.booked_end).getTime()) / 3_600_000));
      const ph = (await q('select price_hour from listings where id = $1', [b.listing_id])).rows[0].price_hour;
      b.overstay_fee_now = r2(hours * Number(ph) * mult);
      b.overstay_hours = hours;
    }
    b.viewer = isDriver ? 'driver' : b.host_id === userId ? 'host' : 'admin';
    return b;
  }

  async listFor(userId: string, role: 'driver' | 'host') {
    const col = role === 'driver' ? 'b.driver_id' : 'b.host_id';
    const { rows } = await this.db.query(
      `select b.id, b.reference, b.status, b.booked_start, b.booked_end, b.actual_parked_at, b.actual_ended_at,
              b.total_amount, b.commission_amount, b.host_earnings, b.listing_id, l.title,
              ${role === 'driver' ? `case when b.status in ('confirmed','parked','overstay','completed') then l.address end as address, hu.name as other_name`
                                  : `du.name as other_name`}, v.plate,
              exists (select 1 from reviews r where r.booking_id = b.id and r.from_user_id = $1) as reviewed
       from bookings b join listings l on l.id = b.listing_id
       join users du on du.id = b.driver_id join users hu on hu.id = b.host_id
       left join vehicles v on v.id = b.vehicle_id
       where ${col} = $1 and b.status <> 'pending_payment'
       order by b.booked_start desc limit 200`, [userId]);
    return rows.map((r) => ({ ...r, other_name: String(r.other_name).split(' ')[0] }));
  }

  private event(c: PoolClient, bookingId: string, event: string, actor: string, actorId: string | null = null,
    geo?: { latitude?: number; longitude?: number }) {
    return c.query(
      `insert into booking_events (booking_id, event, actor, actor_id, latitude, longitude) values ($1,$2,$3,$4,$5,$6)`,
      [bookingId, event, actor, actorId, geo?.latitude ?? null, geo?.longitude ?? null]);
  }
}
