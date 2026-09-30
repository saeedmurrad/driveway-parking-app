import { BadRequestException, Body, Controller, Get, NotFoundException, Param, Post, Put, Query, UseGuards } from '@nestjs/common';
import { DbService } from '../db/db.service';
import { AdminGuard } from '../auth/auth.guard';
import { NotificationsService } from '../notifications/notifications.service';

const EDITABLE: Record<string, [number, number]> = {
  commission_rate: [0, 0.5], grace_minutes: [0, 240], dispute_window_minutes: [0, 10080],
  buffer_minutes: [0, 120], min_payout_gbp: [0, 1000],
};

@Controller('admin')
@UseGuards(AdminGuard)
export class AdminController {
  constructor(private readonly db: DbService, private readonly notes: NotificationsService) {}

  @Get('stats') async stats() {
    const one = async (sql: string) => (await this.db.query(sql)).rows[0];
    const t = await one(`select
        (select count(*) from bookings where created_at::date = now()::date and status <> 'pending_payment')::int as bookings_today,
        (select count(*) from bookings where status in ('parked','overstay'))::int as active_now,
        (select coalesce(sum(amount),0) from transactions where type = 'charge') as gross,
        (select coalesce(sum(amount),0) from transactions where type = 'refund') as refunds,
        (select coalesce(sum(amount),0) from transactions where type = 'commission') as commission,
        (select count(*) from users)::int as users,
        (select count(*) from listings where status = 'pending_approval')::int as pending_listings`);
    return { ...t, gross: Number(t.gross) - Number(t.refunds) };
  }

  @Get('listings') async listings(@Query('status') status?: string) {
    return (await this.db.query(
      `select l.id, l.title, l.address, l.postcode, l.price_hour, l.space_type, l.status, l.created_at, u.name as host_name
       from listings l join users u on u.id = l.host_id where ($1::text is null or l.status = $1) order by l.created_at desc`, [status ?? null])).rows;
  }

  @Post('listings/:id/status') async setListingStatus(@Param('id') id: string, @Body('status') status: string) {
    if (!['live', 'rejected', 'paused', 'removed'].includes(status)) throw new BadRequestException('Bad status');
    const { rows } = await this.db.query('update listings set status = $2 where id = $1 returning id, status, host_id, title', [id, status]);
    if (!rows[0]) throw new NotFoundException();
    if (status === 'live' || status === 'rejected') {
      await this.notes.notify(rows[0].host_id, status === 'live' ? 'listing_approved' : 'listing_rejected',
        status === 'live' ? 'Your space is live' : 'Your space was not approved',
        status === 'live' ? `${rows[0].title} is now visible to drivers.` : `${rows[0].title} needs changes before it can go live.`,
        { channels: ['push', 'email'] });
    }
    return { id: rows[0].id, status: rows[0].status };
  }

  @Get('bookings') async bookings() {
    return (await this.db.query(
      `select b.id, b.reference, b.status, b.booked_start, b.booked_end, b.total_amount, b.commission_amount, b.commission_rate,
              l.title, du.name as driver_name, hu.name as host_name
       from bookings b join listings l on l.id = b.listing_id join users du on du.id = b.driver_id join users hu on hu.id = b.host_id
       where b.status <> 'pending_payment' order by b.created_at desc limit 100`)).rows;
  }

  @Get('settings') async settings() {
    return (await this.db.query('select key, value from settings order by key')).rows;
  }

  @Put('settings') async setSetting(@Body() d: { key: string; value: string }) {
    const range = EDITABLE[d.key];
    const n = Number(d.value);
    if (!range || isNaN(n) || n < range[0] || n > range[1]) throw new BadRequestException(`Invalid value for ${d.key}`);
    await this.db.query('update settings set value = $2 where key = $1', [d.key, String(n)]);
    return { key: d.key, value: String(n) };
  }
}
