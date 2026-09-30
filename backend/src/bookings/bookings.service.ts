import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { PoolClient } from 'pg';
import { randomBytes } from 'crypto';
import { DbService } from '../db/db.service';
import { SettingsService } from '../settings/settings.service';
import { calculatePrice } from './pricing';
import { refundPercent } from './policy';

const r2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;
const PAID = ['confirmed', 'parked', 'overstay', 'completed'];

@Injectable()
export class BookingsService {
  constructor(private readonly db: DbService, private readonly settings: SettingsService) {}

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
      const { rows } = await c.query(
        `update bookings set status = 'confirmed', stripe_payment_intent = $3
         where id = $1 and driver_id = $2 and status = 'pending_payment' returning *`,
        [id, driverId, 'mock_pi_' + randomBytes(6).toString('hex')]);
      if (!rows[0]) throw new BadRequestException('Booking is not awaiting payment (it may have expired)');
      await c.query(
        `insert into transactions (booking_id, user_id, type, amount, provider_ref) values ($1,$2,'charge',$3,$4)`,
        [id, driverId, rows[0].total_amount, rows[0].stripe_payment_intent]);
      await this.event(c, id, 'paid', 'driver', driverId);
      await this.event(c, id, 'confirmed', 'system');
      return this.detail(driverId, id, c);
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

  /** Completing a booking posts the commission + host earning to the ledger. */
  async complete(c: PoolClient, b: any, actor: 'driver' | 'system', actorId: string | null, event: string) {
    await c.query(`update bookings set status = 'completed', actual_ended_at = now() where id = $1`, [b.id]);
    await c.query(
      `insert into transactions (booking_id, user_id, type, amount) values ($1,null,'commission',$2), ($1,$3,'host_earning',$4)`,
      [b.id, b.commission_amount, b.host_id, b.host_earnings]);
    await this.event(c, b.id, event, actor, actorId);
  }

  async cancel(userId: string, id: string) {
    return this.db.tx(async (c) => {
      const b = (await c.query(
        `select b.*, l.cancellation_policy from bookings b join listings l on l.id = b.listing_id
         where b.id = $1 and (b.driver_id = $2 or b.host_id = $2) for update of b`, [id, userId])).rows[0];
      if (!b) throw new NotFoundException();
      const byHost = b.host_id === userId;
      if (b.status === 'pending_payment') {
        await c.query(`update bookings set status = 'cancelled', cancelled_by = 'driver', cancel_reason = 'abandoned' where id = $1`, [id]);
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
