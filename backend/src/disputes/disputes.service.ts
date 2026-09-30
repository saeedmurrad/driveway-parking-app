import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { DbService } from '../db/db.service';
import { NotificationsService } from '../notifications/notifications.service';
import { BookingsService } from '../bookings/bookings.service';
import { AuditService } from '../audit/audit.service';

export const DISPUTE_TYPES = ['space_occupied', 'extra_not_provided', 'wrong_vehicle', 'damage', 'driver_overstayed', 'other'];

@Injectable()
export class DisputesService {
  constructor(
    private readonly db: DbService, private readonly notes: NotificationsService,
    private readonly bookings: BookingsService, private readonly audit: AuditService,
  ) {}

  /** A problem report. While it is open, the host's earnings for that booking are frozen. */
  async create(userId: string, bookingId: string, d: { type: string; description?: string; extraId?: string; photos?: string[] }) {
    if (!DISPUTE_TYPES.includes(d.type)) throw new BadRequestException('Unknown problem type');
    const b = (await this.db.query(
      `select * from bookings where id = $1 and (driver_id = $2 or host_id = $2) and status in ('confirmed','parked','overstay','completed','cancelled')`,
      [bookingId, userId])).rows[0];
    if (!b) throw new NotFoundException();
    if (d.extraId) {
      const ok = await this.db.query('select 1 from booking_extras where id = $1 and booking_id = $2', [d.extraId, bookingId]);
      if (!ok.rowCount) throw new BadRequestException('That extra is not on this booking');
    }
    const dup = await this.db.query(`select 1 from disputes where booking_id = $1 and opened_by = $2 and type = $3 and status <> 'resolved'`, [bookingId, userId, d.type]);
    if (dup.rowCount) throw new ConflictException('You already reported this problem. Our team is on it.');
    const row = (await this.db.query(
      `insert into disputes (booking_id, opened_by, type, extra_id, description, photos) values ($1,$2,$3,$4,$5,$6) returning *`,
      [bookingId, userId, d.type, d.extraId ?? null, d.description ?? null, d.photos?.slice(0, 5) ?? null])).rows[0];
    const other = userId === b.driver_id ? b.host_id : b.driver_id;
    await this.notes.notify(other, 'dispute', 'A problem was reported', `Booking ${b.reference}: ${d.type.replace(/_/g, ' ')}. Payouts for this booking are paused until it is resolved.`, { ref: ['booking', bookingId] });
    const admins = (await this.db.query('select id from users where is_admin')).rows;
    for (const a of admins) await this.notes.notify(a.id, 'dispute', 'New dispute', `Booking ${b.reference}: ${d.type.replace(/_/g, ' ')}.`, { ref: ['booking', bookingId] });
    return row;
  }

  async list(status?: string) {
    return (await this.db.query(
      `select d.id, d.type, d.status, d.description, d.created_at, d.resolved_at, d.refund_amount,
              b.reference, b.total_amount, b.id as booking_id, l.title,
              split_part(o.name,' ',1) as opened_by_name, (d.opened_by = b.driver_id) as by_driver
       from disputes d join bookings b on b.id = d.booking_id join listings l on l.id = b.listing_id
       join users o on o.id = d.opened_by
       where ($1::text is null or d.status = $1) order by (d.status = 'resolved'), d.created_at desc limit 100`, [status ?? null])).rows;
  }

  async detail(id: string) {
    const d = (await this.db.query(
      `select d.*, b.reference, b.status as booking_status, b.total_amount, b.commission_rate, b.booked_start, b.booked_end,
              l.title, du.name as driver_name, hu.name as host_name, b.driver_id, b.host_id
       from disputes d join bookings b on b.id = d.booking_id join listings l on l.id = b.listing_id
       join users du on du.id = b.driver_id join users hu on hu.id = b.host_id where d.id = $1`, [id])).rows[0];
    if (!d) throw new NotFoundException();
    d.messages = (await this.db.query(
      `select m.text, m.created_at, split_part(u.name,' ',1) as sender from messages m join users u on u.id = m.sender_id where m.booking_id = $1 order by m.created_at`, [d.booking_id])).rows;
    d.events = (await this.db.query('select event, actor, created_at from booking_events where booking_id = $1 order by created_at', [d.booking_id])).rows;
    d.extra = d.extra_id ? (await this.db.query(`select et.name, be.line_total from booking_extras be join extra_types et on et.id = be.extra_type_id where be.id = $1`, [d.extra_id])).rows[0] : null;
    d.refunded = Number((await this.db.query(`select coalesce(sum(amount),0) as r from transactions where booking_id = $1 and type = 'refund'`, [d.booking_id])).rows[0].r);
    return d;
  }

  async review(adminId: string, id: string) {
    const r = await this.db.query(`update disputes set status = 'in_review', admin_id = $2 where id = $1 and status = 'open' returning id`, [id, adminId]);
    if (!r.rowCount) throw new BadRequestException('Dispute is not open');
    await this.audit.log(adminId, 'dispute.review', id);
    return { ok: true };
  }

  /** decision: refund (partial/full) | reject. Optional user action: warn or suspend host/driver. */
  async resolve(adminId: string, id: string, d: { decision: 'refund' | 'reject'; amount?: number; note: string; userAction?: string }) {
    const disp = await this.detail(id);
    if (disp.status === 'resolved') throw new BadRequestException('Already resolved');
    await this.db.tx(async (c) => {
      let refund = 0;
      if (d.decision === 'refund') {
        let amt = Number(d.amount);
        if (disp.extra && amt > Number(disp.extra.line_total) + 0.001) throw new BadRequestException(`An extra-only refund is capped at £${Number(disp.extra.line_total).toFixed(2)}`);
        refund = await this.bookings.refundBooking(c, disp.booking_id, amt, 'admin', adminId, d.note);
      }
      await c.query(
        `update disputes set status = 'resolved', resolution = $2, refund_amount = $3, admin_id = $4, resolved_at = now() where id = $1`,
        [id, d.note, refund || null, adminId]);
      await this.audit.log(adminId, `dispute.${d.decision}`, id, { refund, note: d.note, userAction: d.userAction }, c);
      const ref: [string, string] = ['booking', disp.booking_id];
      for (const uid of [disp.driver_id, disp.host_id]) {
        await this.notes.notify(uid, 'dispute', 'Dispute resolved', `Booking ${disp.reference}: ${d.decision === 'refund' ? `£${refund.toFixed(2)} refunded. ` : 'No refund. '}${d.note}`, { ref, channels: ['push', 'email'], client: c });
      }
      if (d.userAction) {
        const [act, who] = d.userAction.split('_'); // warn_host | suspend_driver ...
        const uid = who === 'host' ? disp.host_id : who === 'driver' ? disp.driver_id : null;
        if (uid && act === 'suspend') {
          await c.query(`update users set account_status = 'suspended' where id = $1`, [uid]);
          await this.audit.log(adminId, 'user.suspend', uid, { via: 'dispute', dispute: id }, c);
        } else if (uid && act === 'warn') {
          await this.notes.notify(uid, 'dispute', 'Warning from ParkSpace', 'A dispute involving you was upheld. Repeated issues can lead to suspension.', { ref, channels: ['push', 'email'], client: c });
          await this.audit.log(adminId, 'user.warn', uid, { dispute: id }, c);
        }
      }
    });
    return this.detail(id);
  }
}
