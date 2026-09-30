import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { DbService } from '../db/db.service';
import { SettingsService } from '../settings/settings.service';
import { BookingsService } from './bookings.service';
import { NotificationsService } from '../notifications/notifications.service';

/** In-process ticker (POC). Production: BullMQ / pg_cron. */
@Injectable()
export class SchedulerService implements OnModuleInit, OnModuleDestroy {
  private readonly log = new Logger('Scheduler');
  private timer?: NodeJS.Timeout;

  constructor(private readonly db: DbService, private readonly settings: SettingsService, private readonly bookings: BookingsService, private readonly notes: NotificationsService) {}

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
    // Request-to-book: the host missed the window, so release the held card.
    await this.db.tx(async (c) => {
      const { rows } = await c.query(
        `update bookings set status = 'cancelled', cancelled_by = 'system', cancel_reason = 'host did not respond'
         where status = 'requested' and respond_by < now() returning id, driver_id, reference`);
      for (const r of rows) {
        await c.query(`insert into booking_events (booking_id, event, actor) values ($1,'expired','system')`, [r.id]);
        await this.notes.notify(r.driver_id, 'booking_declined', 'Request expired',
          `The host did not respond to booking ${r.reference}. Your card hold was released and you were not charged.`, { ref: ['booking', r.id], client: c, channels: ['push', 'email'] });
      }
    });
    // Negotiation windows: unanswered offers expire; accepted offers unpaid after 15 minutes expire.
    await this.db.tx(async (c) => {
      const { rows } = await c.query(
        `update offers set status = 'expired'
         where (status = 'open' and expires_at < now()) or (status = 'accepted' and pay_by < now())
         returning thread_id, driver_id, sent_by, status, listing_id`);
      for (const o of rows) {
        await this.notes.notify(o.driver_id, 'offer_expired', 'Offer expired', 'Your negotiation timed out. You can still book at the listed price.', { ref: ['offer', o.thread_id], client: c, dedupe: true });
      }
    });
    await this.reminders();
    // After end + grace: never-parked bookings close as no-shows; parked ones ask the host if the car is still there.
    const grace = await this.settings.getNumber('grace_minutes');
    const respond = await this.settings.getNumber('overstay_response_minutes');
    await this.db.tx(async (c) => {
      const noShow = await c.query(
        `select * from bookings where status = 'confirmed' and booked_end + make_interval(mins => $1) < now() for update`, [grace]);
      for (const b of noShow.rows) {
        await this.bookings.complete(c, b, 'system', null, 'auto_ended');
        this.log.log(`Auto-ended (no-show) ${b.reference}`);
      }
      const ask = await c.query(
        `update bookings set overstay_check = 'asked', overstay_asked_at = now()
         where status = 'parked' and overstay_check is null and booked_end + make_interval(mins => $1) < now()
         returning id, host_id, driver_id, reference`, [grace]);
      for (const b of ask.rows) {
        await this.notes.notify(b.host_id, 'overstay_check', 'Is the car still there?',
          `Booking ${b.reference} has ended but the driver has not checked out. Please confirm.`, { ref: ['booking', b.id], client: c, channels: ['push', 'sms'] });
        await this.notes.notify(b.driver_id, 'overstay_warning', 'Please end your booking',
          `Booking ${b.reference} has ended. Tap End Booking when your car has left to avoid overstay fees.`, { ref: ['booking', b.id], client: c, channels: ['push', 'sms'] });
      }
      // No host answer in time: close at the booked end, no fee.
      const silent = await c.query(
        `select * from bookings where status = 'parked' and overstay_check = 'asked'
           and overstay_asked_at < now() - make_interval(mins => $1) for update`, [respond]);
      for (const b of silent.rows) {
        await c.query(`update bookings set overstay_check = 'gone' where id = $1`, [b.id]);
        await this.bookings.complete(c, b, 'system', null, 'auto_ended', true);
        this.log.log(`Auto-ended (host silent) ${b.reference}`);
      }
    });
  }

  /** Spec section 12 reminders. `dedupe` makes each fire once per booking. */
  private async reminders() {
    const due = async (sql: string) => (await this.db.query(sql)).rows;
    for (const b of await due(`select id, reference, driver_id from bookings where status = 'confirmed'
        and booked_start between now() and now() + interval '30 minutes'`)) {
      await this.notes.notify(b.driver_id, 'reminder_start', 'Your booking starts soon',
        `Booking ${b.reference} starts within 30 minutes. Tap for directions.`, { ref: ['booking', b.id], dedupe: true });
    }
    for (const b of await due(`select id, reference, driver_id from bookings where status in ('confirmed','parked')
        and booked_end between now() and now() + interval '15 minutes'`)) {
      await this.notes.notify(b.driver_id, 'reminder_end', 'Booking ends in 15 minutes',
        `Booking ${b.reference} is about to end. Extend it if you need longer.`, { ref: ['booking', b.id], dedupe: true });
    }
    for (const b of await due(`select id, reference, driver_id from bookings where status = 'confirmed'
        and booked_start < now() - interval '30 minutes' and booked_end > now()`)) {
      await this.notes.notify(b.driver_id, 'reminder_parked', "Haven't parked yet?",
        `Booking ${b.reference} started 30 minutes ago. Tap I've Parked when you arrive.`, { ref: ['booking', b.id], dedupe: true });
    }
  }
}
