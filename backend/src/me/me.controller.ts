import { BadRequestException, Body, Controller, Delete, Get, Post, UseGuards } from '@nestjs/common';
import { IsBoolean, IsIn, IsOptional, IsString, IsUUID, Length, Matches, MinLength } from 'class-validator';
import { DbService } from '../db/db.service';
import { AuthService, AuthUser } from '../auth/auth.service';
import { AuthGuard, CurrentUser } from '../auth/auth.guard';
import { BookingsService } from '../bookings/bookings.service';
import { SettingsService } from '../settings/settings.service';
import { NotificationsService } from '../notifications/notifications.service';

class CodeDto { @IsString() @Length(6, 6) code: string; }
class PhoneDto { @IsString() @Matches(/^\+?[0-9 ()-]{9,16}$/) phone: string; }
class BlockDto { @IsUUID() userId: string; }
class VehicleDto {
  @IsString() @MinLength(2) plate: string;
  @IsOptional() @IsString() make?: string;
  @IsOptional() @IsString() model?: string;
  @IsIn(['small', 'medium', 'large', 'van']) size: string;
  @IsOptional() @IsBoolean() isEv?: boolean;
  @IsOptional() @IsIn(['type2', 'ccs', 'chademo']) evConnector?: string;
}

const r2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;
const startOf = (unit: 'month' | 'year') => {
  const d = new Date();
  return unit === 'month' ? new Date(d.getFullYear(), d.getMonth(), 1) : new Date(d.getFullYear(), 0, 1);
};

@Controller('me')
@UseGuards(AuthGuard)
export class MeController {
  constructor(
    private readonly db: DbService, private readonly bookings: BookingsService,
    private readonly settings: SettingsService, private readonly auth: AuthService,
    private readonly notes: NotificationsService,
  ) {}

  @Get('vehicles') async vehicles(@CurrentUser() u: AuthUser) {
    return (await this.db.query('select * from vehicles where user_id = $1 order by plate', [u.id])).rows;
  }

  @Post('vehicles') async addVehicle(@CurrentUser() u: AuthUser, @Body() d: VehicleDto) {
    return (await this.db.query(
      `insert into vehicles (user_id, plate, make, model, size, is_ev, ev_connector) values ($1, upper($2), $3, $4, $5, $6, $7) returning *`,
      [u.id, d.plate, d.make ?? null, d.model ?? null, d.size, !!d.isEv, d.isEv ? d.evConnector ?? 'type2' : null])).rows[0];
  }

  @Post('become-host') async becomeHost(@CurrentUser() u: AuthUser) {
    await this.db.query('update users set is_host = true where id = $1', [u.id]);
    return this.auth.refresh(u.id);
  }

  // ---- verification (email + SMS codes; shown in the response only in DEMO_MODE)
  @Get('verification') async verification(@CurrentUser() u: AuthUser) {
    const r = (await this.db.query('select email_verified, phone_verified, phone, verification_status from users where id = $1', [u.id])).rows[0];
    return { emailVerified: r.email_verified, phoneVerified: r.phone_verified, phone: r.phone, status: r.verification_status };
  }

  @Post('resend-email') async resendEmail(@CurrentUser() u: AuthUser) {
    return { devCode: await this.auth.issueCode(u.id, 'email') };
  }

  @Post('verify-email') async verifyEmail(@CurrentUser() u: AuthUser, @Body() d: CodeDto) {
    await this.auth.consumeCode(u.id, 'email', d.code);
    await this.db.query('update users set email_verified = true where id = $1', [u.id]);
    return this.auth.refresh(u.id);
  }

  @Post('phone') async sendPhoneCode(@CurrentUser() u: AuthUser, @Body() d: PhoneDto) {
    return { devCode: await this.auth.issueCode(u.id, 'phone', d.phone) };
  }

  @Post('verify-phone') async verifyPhone(@CurrentUser() u: AuthUser, @Body() d: CodeDto) {
    const phone = await this.auth.consumeCode(u.id, 'phone', d.code);
    await this.db.query('update users set phone_verified = true, phone = $2 where id = $1', [u.id, phone]);
    return this.auth.refresh(u.id);
  }

  // ---- block other users
  @Post('block') async block(@CurrentUser() u: AuthUser, @Body() d: BlockDto) {
    if (d.userId === u.id) throw new BadRequestException('You cannot block yourself');
    await this.db.query('insert into user_blocks (blocker_id, blocked_id) values ($1,$2) on conflict do nothing', [u.id, d.userId]);
    return { ok: true };
  }

  // ---- UK GDPR: data export and deletion (financial records are kept, everything else is anonymised)
  @Get('export') async exportData(@CurrentUser() u: AuthUser) {
    const one = async (t: string) => (await this.db.query(t, [u.id])).rows;
    return {
      exportedAt: new Date().toISOString(),
      profile: (await one('select id, name, email, phone, is_driver, is_host, verification_status, terms_version, terms_accepted_at, created_at from users where id = $1'))[0],
      vehicles: await one('select plate, make, model, colour, size, is_ev, ev_connector from vehicles where user_id = $1'),
      listings: await one('select id, title, address, postcode, price_hour, status, created_at from listings where host_id = $1'),
      bookings: await one('select reference, status, booked_start, booked_end, total_amount, commission_amount, host_earnings, created_at from bookings where driver_id = $1 or host_id = $1'),
      transactions: await one('select booking_id, type, amount, currency, created_at from transactions where user_id = $1'),
      reviews: await one('select booking_id, stars, comment, created_at from reviews where from_user_id = $1 or to_user_id = $1'),
      messages: await one('select booking_id, text, created_at from messages where sender_id = $1'),
      notifications: await one('select type, title, body, created_at from notifications where user_id = $1'),
    };
  }

  @Delete() async deleteAccount(@CurrentUser() u: AuthUser) {
    const open = await this.db.query(
      `select 1 from bookings where (driver_id = $1 or host_id = $1) and status in ('requested','confirmed','parked','overstay') limit 1`, [u.id]);
    if (open.rowCount) throw new BadRequestException('Please cancel or finish your upcoming and active bookings before deleting your account.');
    await this.db.tx(async (c) => {
      await c.query(
        `update users set name = 'Deleted user', email = 'deleted-' || id || '@deleted.invalid', phone = null, password_hash = null,
           photo_url = null, account_status = 'deleted', is_host = false where id = $1`, [u.id]);
      await c.query('delete from vehicles where user_id = $1 and not exists (select 1 from bookings b where b.vehicle_id = vehicles.id)', [u.id]);
      await c.query(`update listings set status = 'removed' where host_id = $1`, [u.id]);
      await c.query('delete from notifications where user_id = $1', [u.id]);
      await c.query('delete from verification_codes where user_id = $1', [u.id]);
    });
    this.auth.forget(u.id);
    return { ok: true };
  }

  @Get('notifications') notifications(@CurrentUser() u: AuthUser) { return this.notes.list(u.id); }
  @Post('notifications/read') readAll(@CurrentUser() u: AuthUser) { return this.notes.markAllRead(u.id); }

  @Get('bookings') driverBookings(@CurrentUser() u: AuthUser) { return this.bookings.listFor(u.id, 'driver'); }
  @Get('host-bookings') hostBookings(@CurrentUser() u: AuthUser) { return this.bookings.listFor(u.id, 'host'); }

  @Get('listings') async listings(@CurrentUser() u: AuthUser) {
    return (await this.db.query(
      `select l.*, (select count(*) from bookings b where b.listing_id = l.id and b.status = 'completed')::int as bookings_count,
              coalesce((select sum(b.host_earnings) from bookings b where b.listing_id = l.id and b.status = 'completed'), 0) as earnings
       from listings l where l.host_id = $1 and l.status <> 'removed' order by l.created_at desc`, [u.id])).rows;
  }

  /** Spending is derived from the ledger (SUMs), never a stored balance. */
  @Get('driver-summary') async driverSummary(@CurrentUser() u: AuthUser) {
    const { rows } = await this.db.query(
      `select type, amount, created_at from transactions where user_id = $1 and type in ('charge','refund','overstay_fee')`, [u.id]);
    const net = (from?: Date) => r2(rows.filter((r) => !from || r.created_at >= from)
      .reduce((s, r) => s + (r.type === 'refund' ? -1 : 1) * Number(r.amount), 0));
    const count = (await this.db.query(`select count(*)::int as n from bookings where driver_id = $1 and status in ('confirmed','parked','overstay','completed')`, [u.id])).rows[0].n;
    return { month: net(startOf('month')), year: net(startOf('year')), allTime: net(), bookings: count };
  }

  @Get('host-summary') async hostSummary(@CurrentUser() u: AuthUser) {
    const windowMin = await this.settings.getNumber('dispute_window_minutes');
    const { rows } = await this.db.query(
      `select t.type, t.amount, t.created_at,
              (t.booking_id is not null and exists (select 1 from disputes d where d.booking_id = t.booking_id and d.status in ('open','in_review'))) as frozen
       from transactions t where t.user_id = $1 and t.type in ('host_earning','payout')`, [u.id]);
    const cutoff = new Date(Date.now() - windowMin * 60_000);
    const earned = rows.filter((r) => r.type === 'host_earning');
    const sum = (a: any[]) => a.reduce((s, r) => s + Number(r.amount), 0);
    const paidOut = sum(rows.filter((r) => r.type === 'payout'));
    // Earnings are released after the dispute window; refund adjustments (negative) apply at once;
    // anything attached to a booking with an open dispute is frozen until Admin decides.
    const isReleased = (r: any) => !r.frozen && (Number(r.amount) < 0 || r.created_at <= cutoff);
    const released = sum(earned.filter(isReleased));
    const frozen = sum(earned.filter((r) => r.frozen));
    const total = (from?: Date) => r2(sum(earned.filter((r) => !from || r.created_at >= from)));
    const payouts = (await this.db.query(
      `select id, amount, status, sent_at from payouts where host_id = $1 order by sent_at desc nulls last limit 20`, [u.id])).rows;
    return {
      pending: r2(sum(earned) - released - frozen), frozen: r2(frozen), available: r2(released - paidOut), paidOut: r2(paidOut),
      month: total(startOf('month')), year: total(startOf('year')), allTime: total(),
      minPayout: await this.settings.getNumber('min_payout_gbp'), disputeWindowMinutes: windowMin, payouts,
    };
  }

  @Post('payout') async payout(@CurrentUser() u: AuthUser) {
    const s = await this.hostSummary(u);
    if (s.available < s.minPayout) throw new BadRequestException(`Minimum payout is £${s.minPayout.toFixed(2)}`);
    return this.db.tx(async (c) => {
      const p = (await c.query(
        `insert into payouts (host_id, amount, provider_ref, status, sent_at) values ($1,$2,$3,'paid',now()) returning *`,
        [u.id, s.available, 'mock_po_' + Date.now()])).rows[0];
      await c.query(`insert into transactions (user_id, type, amount, provider_ref) values ($1,'payout',$2,$3)`, [u.id, s.available, p.provider_ref]);
      await this.notes.notify(u.id, 'payout', 'Payout sent', `£${s.available.toFixed(2)} is on its way to your bank.`, { channels: ['push', 'email'], client: c });
      return p;
    });
  }
}
