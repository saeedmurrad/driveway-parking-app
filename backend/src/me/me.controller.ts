import { BadRequestException, Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { IsIn, IsOptional, IsString, MinLength } from 'class-validator';
import { DbService } from '../db/db.service';
import { AuthService, AuthUser } from '../auth/auth.service';
import { AuthGuard, CurrentUser } from '../auth/auth.guard';
import { BookingsService } from '../bookings/bookings.service';
import { SettingsService } from '../settings/settings.service';
import { NotificationsService } from '../notifications/notifications.service';

class VehicleDto {
  @IsString() @MinLength(2) plate: string;
  @IsOptional() @IsString() make?: string;
  @IsOptional() @IsString() model?: string;
  @IsIn(['small', 'medium', 'large', 'van']) size: string;
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
      `insert into vehicles (user_id, plate, make, model, size) values ($1, upper($2), $3, $4, $5) returning *`,
      [u.id, d.plate, d.make ?? null, d.model ?? null, d.size])).rows[0];
  }

  @Post('become-host') async becomeHost(@CurrentUser() u: AuthUser) {
    await this.db.query('update users set is_host = true where id = $1', [u.id]);
    return this.auth.refresh(u.id);
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
      `select type, amount, created_at from transactions where user_id = $1 and type in ('host_earning','payout')`, [u.id]);
    const cutoff = new Date(Date.now() - windowMin * 60_000);
    const earned = rows.filter((r) => r.type === 'host_earning');
    const sum = (a: any[]) => a.reduce((s, r) => s + Number(r.amount), 0);
    const paidOut = sum(rows.filter((r) => r.type === 'payout'));
    const released = sum(earned.filter((r) => r.created_at <= cutoff));
    const total = (from?: Date) => r2(sum(earned.filter((r) => !from || r.created_at >= from)));
    const payouts = (await this.db.query(
      `select id, amount, status, sent_at from payouts where host_id = $1 order by sent_at desc nulls last limit 20`, [u.id])).rows;
    return {
      pending: r2(sum(earned) - released), available: r2(released - paidOut), paidOut: r2(paidOut),
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
