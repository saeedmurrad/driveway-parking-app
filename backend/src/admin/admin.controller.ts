import { BadRequestException, Body, Controller, Get, NotFoundException, Param, Patch, Post, Put, Query, UseGuards } from '@nestjs/common';
import { DbService } from '../db/db.service';
import { AdminGuard, CurrentUser } from '../auth/auth.guard';
import { AuthService, AuthUser } from '../auth/auth.service';
import { NotificationsService } from '../notifications/notifications.service';
import { AuditService } from '../audit/audit.service';
import { BookingsService } from '../bookings/bookings.service';
import { DisputesService } from '../disputes/disputes.service';

const EDITABLE: Record<string, [number, number]> = {
  commission_rate: [0, 0.5], grace_minutes: [0, 240], dispute_window_minutes: [0, 10080],
  buffer_minutes: [0, 120], min_payout_gbp: [0, 1000], overstay_multiplier: [1, 5],
  overstay_response_minutes: [1, 1440], request_response_minutes: [1, 240],
};

@Controller('admin')
@UseGuards(AdminGuard)
export class AdminController {
  constructor(
    private readonly db: DbService, private readonly notes: NotificationsService, private readonly audit: AuditService,
    private readonly bookings: BookingsService, private readonly disputes: DisputesService, private readonly auth: AuthService,
  ) {}

  @Get('stats') async stats() {
    const t = (await this.db.query(`select
        (select count(*) from bookings where created_at::date = now()::date and status not in ('pending_payment'))::int as bookings_today,
        (select count(*) from bookings where status in ('parked','overstay'))::int as active_now,
        (select coalesce(sum(amount),0) from transactions where type in ('charge','overstay_fee')) as gross,
        (select coalesce(sum(amount),0) from transactions where type = 'refund') as refunds,
        (select coalesce(sum(amount),0) from transactions where type = 'commission') as commission,
        (select count(*) from users)::int as users,
        (select count(*) from listings where status = 'pending_approval')::int as pending_listings,
        (select count(*) from disputes where status <> 'resolved')::int as open_disputes,
        (select count(*) from users where rating_as_driver < 3 or rating_as_host < 3)::int as low_rated`)).rows[0];
    return { ...t, gross: Number(t.gross) - Number(t.refunds) };
  }

  // ---- listings
  @Get('listings') async listings(@Query('status') status?: string) {
    return (await this.db.query(
      `select l.id, l.title, l.address, l.postcode, l.price_hour, l.space_type, l.status, l.created_at, l.permission_declared_at,
              u.name as host_name, u.verification_status as host_verification, u.id as host_id
       from listings l join users u on u.id = l.host_id where ($1::text is null or l.status = $1) order by l.created_at desc`, [status ?? null])).rows;
  }

  @Post('listings/:id/status') async setListingStatus(@CurrentUser() a: AuthUser, @Param('id') id: string, @Body('status') status: string) {
    if (!['live', 'rejected', 'paused', 'removed'].includes(status)) throw new BadRequestException('Bad status');
    const { rows } = await this.db.query('update listings set status = $2 where id = $1 returning id, status, host_id, title', [id, status]);
    if (!rows[0]) throw new NotFoundException();
    await this.audit.log(a.id, `listing.${status}`, id, { title: rows[0].title });
    if (status === 'live' || status === 'rejected') {
      await this.notes.notify(rows[0].host_id, status === 'live' ? 'listing_approved' : 'listing_rejected',
        status === 'live' ? 'Your space is live' : 'Your space was not approved',
        status === 'live' ? `${rows[0].title} is now visible to drivers.` : `${rows[0].title} needs changes before it can go live.`,
        { channels: ['push', 'email'] });
    }
    return { id: rows[0].id, status: rows[0].status };
  }

  // ---- bookings
  @Get('bookings') async bookingsList() {
    return (await this.db.query(
      `select b.id, b.reference, b.status, b.booked_start, b.booked_end, b.total_amount, b.commission_amount, b.commission_rate,
              l.title, du.name as driver_name, hu.name as host_name, v.plate,
              coalesce((select sum(amount) from transactions t where t.booking_id = b.id and t.type = 'refund'),0) as refunded
       from bookings b join listings l on l.id = b.listing_id join users du on du.id = b.driver_id join users hu on hu.id = b.host_id
       left join vehicles v on v.id = b.vehicle_id
       where b.status <> 'pending_payment' order by b.created_at desc limit 150`)).rows;
  }

  @Post('bookings/:id/refund') async refund(@CurrentUser() a: AuthUser, @Param('id') id: string, @Body() d: { amount: number; reason?: string }) {
    const amt = await this.db.tx((c) => this.bookings.refundBooking(c, id, Number(d.amount), 'admin', a.id, d.reason));
    await this.audit.log(a.id, 'booking.refund', id, { amount: amt, reason: d.reason });
    return { refunded: amt };
  }

  @Post('bookings/:id/force-end') async forceEnd(@CurrentUser() a: AuthUser, @Param('id') id: string) {
    const r = await this.bookings.adminForceEnd(a.id, id);
    await this.audit.log(a.id, 'booking.force_end', id);
    return r;
  }

  // ---- users
  @Get('users') async users(@Query('q') q?: string) {
    return (await this.db.query(
      `select u.id, u.name, u.email, u.is_host, u.is_admin, u.verification_status, u.account_status, u.email_verified, u.phone_verified,
              u.rating_as_driver, u.rating_as_host, u.created_at,
              (select count(*) from bookings b where b.driver_id = u.id or b.host_id = u.id)::int as bookings
       from users u where $1::text is null or u.name ilike '%'||$1||'%' or u.email ilike '%'||$1||'%'
       order by u.created_at desc limit 100`, [q || null])).rows;
  }

  @Post('users/:id/status') async userStatus(@CurrentUser() a: AuthUser, @Param('id') id: string, @Body('status') status: string) {
    if (!['active', 'suspended'].includes(status)) throw new BadRequestException('Status must be active or suspended');
    if (id === a.id) throw new BadRequestException('You cannot change your own status');
    const r = await this.db.query(`update users set account_status = $2 where id = $1 and account_status <> 'deleted' returning id, account_status`, [id, status]);
    if (!r.rowCount) throw new NotFoundException();
    this.auth.forget(id);
    await this.audit.log(a.id, `user.${status === 'active' ? 'reinstate' : 'suspend'}`, id);
    return r.rows[0];
  }

  @Post('users/:id/verify') async verifyUser(@CurrentUser() a: AuthUser, @Param('id') id: string) {
    const r = await this.db.query(`update users set verification_status = 'verified' where id = $1 returning id`, [id]);
    if (!r.rowCount) throw new NotFoundException();
    await this.audit.log(a.id, 'user.verify', id);
    return { ok: true };
  }

  // ---- disputes
  @Get('disputes') disputeList(@Query('status') status?: string) { return this.disputes.list(status); }
  @Get('disputes/:id') disputeOne(@Param('id') id: string) { return this.disputes.detail(id); }
  @Post('disputes/:id/review') disputeReview(@CurrentUser() a: AuthUser, @Param('id') id: string) { return this.disputes.review(a.id, id); }
  @Post('disputes/:id/resolve') disputeResolve(@CurrentUser() a: AuthUser, @Param('id') id: string,
    @Body() d: { decision: 'refund' | 'reject'; amount?: number; note: string; userAction?: string }) {
    if (!d.note?.trim()) throw new BadRequestException('Add a note explaining the decision');
    return this.disputes.resolve(a.id, id, d);
  }

  // ---- settings
  @Get('settings') async settings() {
    return (await this.db.query('select key, value from settings order by key')).rows;
  }

  @Put('settings') async setSetting(@CurrentUser() a: AuthUser, @Body() d: { key: string; value: string }) {
    const range = EDITABLE[d.key];
    const n = Number(d.value);
    if (!range || isNaN(n) || n < range[0] || n > range[1]) throw new BadRequestException(`Invalid value for ${d.key}`);
    const old = (await this.db.query('select value from settings where key = $1', [d.key])).rows[0]?.value;
    await this.db.query('update settings set value = $2 where key = $1', [d.key, String(n)]);
    await this.audit.log(a.id, 'setting.change', d.key, { from: old, to: String(n) });
    return { key: d.key, value: String(n) };
  }

  // ---- extras catalogue
  @Get('extra-types') async extraTypes() {
    return (await this.db.query('select id, name, description, allowed_price_units, ev_only, active from extra_types order by name')).rows;
  }

  @Post('extra-types') async addExtraType(@CurrentUser() a: AuthUser, @Body() d: { name: string; description?: string; allowedPriceUnits?: string[]; evOnly?: boolean }) {
    if (!d.name?.trim()) throw new BadRequestException('Name is required');
    const units = (d.allowedPriceUnits?.length ? d.allowedPriceUnits : ['per_booking']).filter((u) => ['per_booking', 'per_hour', 'per_day', 'per_kwh'].includes(u));
    const row = (await this.db.query(
      'insert into extra_types (name, description, allowed_price_units, ev_only) values ($1,$2,$3,$4) returning *',
      [d.name.trim(), d.description ?? null, units, !!d.evOnly])).rows[0];
    await this.audit.log(a.id, 'extra_type.create', row.id, { name: row.name });
    return row;
  }

  @Patch('extra-types/:id') async patchExtraType(@CurrentUser() a: AuthUser, @Param('id') id: string, @Body() d: { active?: boolean; name?: string; description?: string }) {
    const { rows } = await this.db.query(
      `update extra_types set active = coalesce($2, active), name = coalesce($3, name), description = coalesce($4, description)
       where id = $1 returning *`, [id, d.active ?? null, d.name ?? null, d.description ?? null]);
    if (!rows[0]) throw new NotFoundException();
    await this.audit.log(a.id, 'extra_type.update', id, d);
    return rows[0];
  }

  // ---- content, announcements, audit
  @Put('content/:key') async setContent(@CurrentUser() a: AuthUser, @Param('key') key: string, @Body() d: { body: string; title?: string }) {
    if (!d.body?.trim()) throw new BadRequestException('Content cannot be empty');
    const r = await this.db.query(
      `update content set body = $2, title = coalesce($3, title), version = version + 1, updated_at = now() where key = $1 returning key, version`,
      [key, d.body, d.title ?? null]);
    if (!r.rowCount) throw new NotFoundException();
    await this.audit.log(a.id, 'content.update', key, { version: r.rows[0].version });
    return r.rows[0];
  }

  @Post('announce') async announce(@CurrentUser() a: AuthUser, @Body() d: { title: string; body: string }) {
    if (!d.title?.trim() || !d.body?.trim()) throw new BadRequestException('Title and message are required');
    const users = (await this.db.query(`select id from users where account_status = 'active'`)).rows;
    for (const u of users) await this.notes.notify(u.id, 'announcement', d.title.trim(), d.body.trim(), { channels: ['push'] });
    await this.audit.log(a.id, 'announcement.send', null, { title: d.title, recipients: users.length });
    return { sent: users.length };
  }

  @Get('audit') async auditLog() {
    return (await this.db.query(
      `select l.id, l.action, l.target, l.details, l.created_at, u.name as admin_name
       from admin_audit_log l left join users u on u.id = l.admin_id order by l.created_at desc limit 200`)).rows;
  }
}
