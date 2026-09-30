import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { randomBytes } from 'crypto';
import { DbService } from '../db/db.service';
import { SettingsService } from '../settings/settings.service';
import { calculatePrice } from './pricing';

@Injectable()
export class BookingsService {
  constructor(private readonly db: DbService, private readonly settings: SettingsService) {}

  async create(dto: { listingId: string; driverId: string; vehicleId?: string; start: string; end: string }) {
    const start = new Date(dto.start);
    const end = new Date(dto.end);
    if (!(end > start) || start < new Date()) throw new BadRequestException('Invalid time window');

    const rate = await this.settings.getNumber('commission_rate');

    return this.db.tx(async (c) => {
      const l = (await c.query(
        `select host_id, price_hour, price_day, buffer_minutes from listings
         where id = $1 and status = 'live'`, [dto.listingId])).rows[0];
      if (!l) throw new NotFoundException('Listing not available');

      const price = calculatePrice({
        start, end, priceHour: Number(l.price_hour),
        priceDay: l.price_day == null ? null : Number(l.price_day), commissionRate: rate,
      });
      const blockedEnd = new Date(end.getTime() + l.buffer_minutes * 60_000);
      const reference = 'PS-' + randomBytes(3).toString('hex').toUpperCase();

      try {
        // The exclusion constraint `no_double_booking` rejects overlaps atomically.
        const { rows } = await c.query(
          `insert into bookings (reference, listing_id, driver_id, host_id, vehicle_id,
             booked_start, booked_end, blocked_end, parking_amount, extras_amount, total_amount,
             commission_rate, commission_amount, host_earnings, status)
           values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,'pending_payment')
           returning *`,
          [reference, dto.listingId, dto.driverId, l.host_id, dto.vehicleId ?? null,
           start, end, blockedEnd, price.parking, price.extras, price.total,
           price.commissionRate, price.commission, price.hostEarnings]);
        await c.query(
          `insert into booking_events (booking_id, event, actor, actor_id) values ($1,'created','driver',$2)`,
          [rows[0].id, dto.driverId]);
        // TODO(stripe): create PaymentIntent here; confirm booking in the webhook handler.
        return { booking: rows[0], price };
      } catch (e: any) {
        if (e.code === '23P01') throw new ConflictException('That time slot has just been taken');
        throw e;
      }
    });
  }

  async get(id: string) {
    const { rows } = await this.db.query('select * from bookings where id = $1', [id]);
    if (!rows[0]) throw new NotFoundException();
    return rows[0];
  }

  async markParked(id: string, dto: { driverId: string; latitude?: number; longitude?: number }) {
    return this.transition(id, dto.driverId, ['confirmed'], 'parked', 'parked', 'actual_parked_at', dto);
  }

  async end(id: string, driverId: string) {
    return this.transition(id, driverId, ['parked', 'overstay'], 'completed', 'ended', 'actual_ended_at');
  }

  private async transition(
    id: string, driverId: string, from: string[], to: string, event: string,
    stampCol: string, geo?: { latitude?: number; longitude?: number },
  ) {
    return this.db.tx(async (c) => {
      const { rows } = await c.query(
        `update bookings set status = $1, ${stampCol} = now()
         where id = $2 and driver_id = $3 and status = any($4) returning *`,
        [to, id, driverId, from]);
      if (!rows[0]) throw new BadRequestException(`Booking cannot move to ${to}`);
      await c.query(
        `insert into booking_events (booking_id, event, actor, actor_id, latitude, longitude)
         values ($1,$2,'driver',$3,$4,$5)`,
        [id, event, driverId, geo?.latitude ?? null, geo?.longitude ?? null]);
      return rows[0];
    });
  }
}
