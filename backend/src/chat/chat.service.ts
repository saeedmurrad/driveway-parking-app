import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { DbService } from '../db/db.service';
import { NotificationsService } from '../notifications/notifications.service';

/** In-app chat between driver and host, only once a booking is paid; saved for disputes. */
@Injectable()
export class ChatService {
  constructor(private readonly db: DbService, private readonly notes: NotificationsService) {}

  private async booking(userId: string, bookingId: string) {
    const b = (await this.db.query(
      `select b.id, b.driver_id, b.host_id, b.status, b.reference,
              exists (select 1 from users where id = $2 and is_admin) as admin
       from bookings b where b.id = $1`, [bookingId, userId])).rows[0];
    if (!b || (b.driver_id !== userId && b.host_id !== userId && !b.admin)) throw new NotFoundException();
    return b;
  }

  async list(userId: string, bookingId: string) {
    await this.booking(userId, bookingId);
    return (await this.db.query(
      `select m.id, m.sender_id, m.text, m.created_at, split_part(u.name,' ',1) as sender_name
       from messages m join users u on u.id = m.sender_id where m.booking_id = $1 order by m.created_at`, [bookingId])).rows;
  }

  async send(userId: string, bookingId: string, text: string) {
    const b = await this.booking(userId, bookingId);
    if (b.admin && b.driver_id !== userId && b.host_id !== userId) throw new ForbiddenException('Admins can read but not post');
    if (!['confirmed', 'parked', 'overstay', 'completed'].includes(b.status)) throw new BadRequestException('Chat opens once the booking is confirmed');
    const blocked = await this.db.query(
      `select 1 from user_blocks where (blocker_id = $1 and blocked_id = $2) or (blocker_id = $2 and blocked_id = $1)`, [b.driver_id, b.host_id]);
    if (blocked.rowCount) throw new ForbiddenException('You cannot message this user');
    const clean = text.trim();
    if (!clean) throw new BadRequestException('Type a message');
    const m = (await this.db.query(
      `insert into messages (booking_id, sender_id, text) values ($1,$2,$3) returning id, sender_id, text, created_at`, [bookingId, userId, clean])).rows[0];
    const other = userId === b.driver_id ? b.host_id : b.driver_id;
    const unread = await this.db.query(`select 1 from notifications where user_id = $1 and type = 'message' and ref_id = $2 and not read`, [other, bookingId]);
    if (!unread.rowCount) {
      await this.notes.notify(other, 'message', 'New message', `Booking ${b.reference}: ${clean.slice(0, 80)}`, { ref: ['booking', bookingId] });
    }
    return m;
  }
}
