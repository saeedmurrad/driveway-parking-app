import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { DbService } from '../db/db.service';
import { SettingsService } from '../settings/settings.service';
import { BookingsService } from './bookings.service';

/** In-process ticker (POC). Production: BullMQ / pg_cron. */
@Injectable()
export class SchedulerService implements OnModuleInit, OnModuleDestroy {
  private readonly log = new Logger('Scheduler');
  private timer?: NodeJS.Timeout;

  constructor(private readonly db: DbService, private readonly settings: SettingsService, private readonly bookings: BookingsService) {}

  onModuleInit() { this.timer = setInterval(() => this.tick().catch((e) => this.log.error(e.message)), 30_000); }
  onModuleDestroy() { clearInterval(this.timer); }

  async tick() {
    // Unpaid bookings release their slot after 10 minutes.
    await this.db.tx(async (c) => {
      const { rows } = await c.query(
        `update bookings set status = 'cancelled', cancelled_by = 'system', cancel_reason = 'payment timeout'
         where status = 'pending_payment' and created_at < now() - interval '10 minutes' returning id`);
      for (const r of rows) await c.query(`insert into booking_events (booking_id, event, actor) values ($1,'cancelled','system')`, [r.id]);
    });
    // Auto-end: booked end + grace passed and the driver never tapped End Booking.
    const grace = await this.settings.getNumber('grace_minutes');
    await this.db.tx(async (c) => {
      const { rows } = await c.query(
        `select * from bookings where status in ('confirmed','parked')
           and booked_end + make_interval(mins => $1) < now() for update`, [grace]);
      for (const b of rows) {
        await this.bookings.complete(c, b, 'system', null, 'auto_ended');
        this.log.log(`Auto-ended ${b.reference}`);
      }
    });
  }
}
