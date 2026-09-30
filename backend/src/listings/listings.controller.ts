import { BadRequestException, Body, ConflictException, Controller, Delete, ForbiddenException, Get, NotFoundException, Param, Patch, Post, Put, Query, UseGuards } from '@nestjs/common';
import { ArrayMaxSize, IsArray, IsBoolean, IsIn, IsInt, IsNumber, IsOptional, IsString, Matches, Max, Min, MinLength } from 'class-validator';
import { DbService } from '../db/db.service';
import { AuthUser } from '../auth/auth.service';
import { AuthGuard, CurrentUser } from '../auth/auth.guard';
import { BookingsService } from '../bookings/bookings.service';
import { calculatePrice } from '../bookings/pricing';
import { SettingsService } from '../settings/settings.service';

class ListingBase {
  @IsOptional() @IsString() postcode?: string;
  @IsOptional() @IsIn(['driveway', 'garage', 'bay', 'forecourt']) spaceType?: string;
  @IsOptional() @IsIn(['small', 'medium', 'large', 'van']) maxVehicleSize?: string;
  @IsOptional() @IsNumber() @Min(1) priceDay?: number | null;
  @IsOptional() @IsArray() @ArrayMaxSize(10) features?: string[];
  @IsOptional() @IsString() accessInstructions?: string;
  @IsOptional() @IsIn(['flexible', 'moderate', 'strict']) cancellationPolicy?: string;
  @IsOptional() @IsInt() @Min(15) minStayMinutes?: number;
  @IsOptional() @IsInt() @Min(30) maxStayMinutes?: number;
  @IsOptional() @IsBoolean() allowOffers?: boolean;
  @IsOptional() @IsNumber() @Min(0) minOfferPrice?: number | null;
  @IsOptional() @IsIn(['instant', 'request']) bookingMode?: string;
  @IsOptional() @IsInt() @Min(0) @Max(120) bufferMinutes?: number;
}
class CreateListingDto extends ListingBase {
  @IsString() @MinLength(3) title: string;
  @IsString() @MinLength(3) address: string;
  @IsNumber() @Min(-90) @Max(90) latitude: number;
  @IsNumber() @Min(-180) @Max(180) longitude: number;
  @IsNumber() @Min(0.5) @Max(100) priceHour: number;
}
class ListingFields extends ListingBase {
  @IsOptional() @IsString() @MinLength(3) title?: string;
  @IsOptional() @IsString() @MinLength(3) address?: string;
  @IsOptional() @IsNumber() @Min(-90) @Max(90) latitude?: number;
  @IsOptional() @IsNumber() @Min(-180) @Max(180) longitude?: number;
  @IsOptional() @IsNumber() @Min(0.5) @Max(100) priceHour?: number;
}
class RuleDto {
  @IsInt() @Min(0) @Max(6) dayOfWeek: number;
  @Matches(/^([01]\d|2[0-3]):[0-5]\d$/) start: string;
  @Matches(/^(([01]\d|2[0-3]):[0-5]\d|24:00)$/) end: string;
}
class ListingExtraDto {
  @IsString() extraTypeId: string;
  @IsNumber() @Min(0) @Max(500) price: number;
  @IsIn(['per_booking', 'per_hour', 'per_day', 'per_kwh']) priceUnit: string;
  @IsOptional() details?: Record<string, unknown>;
  @IsOptional() @IsBoolean() active?: boolean;
}
class ExtrasDto {
  @IsArray() extras: ListingExtraDto[];
}
class AvailabilityDto {
  @IsBoolean() always: boolean;
  @IsOptional() @IsArray() rules?: RuleDto[];
}
class BlockDto {
  @IsString() start: string;
  @IsString() end: string;
  @IsOptional() @IsString() reason?: string;
}

// camelCase DTO key -> column
/** "id:qty,id" -> [{id, quantity}] */
export function parseExtras(raw?: string): { id: string; quantity?: number }[] {
  if (!raw) return [];
  return raw.split(',').filter(Boolean).map((p) => {
    const [id, q] = p.split(':');
    return { id, quantity: q ? Number(q) : undefined };
  });
}

const COLS: Record<string, string> = {
  title: 'title', address: 'address', postcode: 'postcode', latitude: 'latitude', longitude: 'longitude',
  spaceType: 'space_type', maxVehicleSize: 'max_vehicle_size', priceHour: 'price_hour', priceDay: 'price_day',
  features: 'features', accessInstructions: 'access_instructions', cancellationPolicy: 'cancellation_policy',
  minStayMinutes: 'min_stay_minutes', maxStayMinutes: 'max_stay_minutes', allowOffers: 'allow_offers',
  minOfferPrice: 'min_offer_price', bookingMode: 'booking_mode', bufferMinutes: 'buffer_minutes',
};

@Controller('listings')
export class ListingsController {
  constructor(
    private readonly db: DbService,
    private readonly bookings: BookingsService,
    private readonly settings: SettingsService,
  ) {}

  /** GET /listings/search?lat=&lng=&start=&end=&radius=&vehicleSize= */
  @Get('search')
  async search(
    @Query('lat') lat: string, @Query('lng') lng: string,
    @Query('start') start: string, @Query('end') end: string,
    @Query('radius') radius = '3000', @Query('vehicleSize') vehicleSize = 'medium',
  ) {
    const s = new Date(start), e = new Date(end);
    if (isNaN(+s) || isNaN(+e) || !(e > s)) throw new BadRequestException('Invalid start/end');
    const { rows } = await this.db.query('select * from search_listings($1,$2,$3,$4,$5,$6)',
      [Number(lat), Number(lng), Number(radius), s, e, vehicleSize]);
    const rate = await this.settings.getNumber('commission_rate');
    return rows.map((r) => ({
      ...r,
      quote: calculatePrice({
        start: s, end: e, priceHour: Number(r.price_hour),
        priceDay: r.price_day == null ? null : Number(r.price_day), commissionRate: rate,
      }),
    }));
  }

  /** Public detail. Exact address + access instructions are released only with a paid booking. */
  @Get(':id')
  async one(@Param('id') id: string, @Query('start') start?: string, @Query('end') end?: string, @Query('extras') extras?: string, @Query('vehicleId') vehicleId?: string) {
    const { rows } = await this.db.query(
      `select l.id, l.title, l.latitude, l.longitude, l.postcode, l.space_type, l.max_vehicle_size, l.features,
              l.price_hour, l.price_day, l.cancellation_policy, l.booking_mode, l.allow_offers, l.rating, l.status,
              l.min_stay_minutes, l.max_stay_minutes,
              split_part(u.name,' ',1) as host_name,
              (select count(*) from reviews r where r.listing_id = l.id)::int as review_count
       from listings l join users u on u.id = l.host_id where l.id = $1 and l.status in ('live','paused')`, [id]);
    if (!rows[0]) throw new NotFoundException();
    const reviews = (await this.db.query(
      `select r.stars, r.comment, r.created_at, split_part(u.name,' ',1) as name
       from reviews r join users u on u.id = r.from_user_id where r.listing_id = $1 order by r.created_at desc limit 5`, [id])).rows;
    const out: any = { ...rows[0], reviews };
    out.extras = (await this.db.query(
      `select le.id, et.name, et.description, le.price, le.price_unit, le.details, et.ev_only
       from listing_extras le join extra_types et on et.id = le.extra_type_id
       where le.listing_id = $1 and le.active and et.active order by et.name`, [id])).rows;
    if (start && end) out.quote = await this.bookings.quote(id, new Date(start), new Date(end), parseExtras(extras), vehicleId);
    return out;
  }

  @Post() @UseGuards(AuthGuard)
  async create(@CurrentUser() u: AuthUser, @Body() d: CreateListingDto) {
    if (!u.isHost) throw new ForbiddenException('Switch to a host account first');
    const cols = ['host_id', 'status'];
    const vals: unknown[] = [u.id, 'pending_approval'];
    for (const [k, col] of Object.entries(COLS)) {
      if ((d as any)[k] !== undefined) { cols.push(col); vals.push((d as any)[k]); }
    }
    const ph = vals.map((_, i) => `$${i + 1}`).join(',');
    const { rows } = await this.db.query(`insert into listings (${cols.join(',')}) values (${ph}) returning *`, vals);
    return rows[0];
  }

  @Patch(':id') @UseGuards(AuthGuard)
  async update(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body() d: ListingFields) {
    const sets: string[] = [];
    const vals: unknown[] = [id, u.id];
    for (const [k, col] of Object.entries(COLS)) {
      if ((d as any)[k] !== undefined) { vals.push((d as any)[k]); sets.push(`${col} = $${vals.length}`); }
    }
    if (!sets.length) throw new BadRequestException('Nothing to update');
    const { rows } = await this.db.query(
      `update listings set ${sets.join(', ')} where id = $1 and host_id = $2 and status <> 'removed' returning *`, vals);
    if (!rows[0]) throw new NotFoundException();
    return rows[0];
  }

  @Patch(':id/status') @UseGuards(AuthGuard)
  async setStatus(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body('status') status: string) {
    if (!['live', 'paused'].includes(status)) throw new BadRequestException('Status must be live or paused');
    const { rows } = await this.db.query(
      `update listings set status = $3 where id = $1 and host_id = $2 and status in ('live','paused') returning *`,
      [id, u.id, status]);
    if (!rows[0]) throw new NotFoundException('Only your approved listings can be paused or resumed');
    return rows[0];
  }

  private async owned(u: AuthUser, id: string) {
    const r = await this.db.query('select 1 from listings where id = $1 and host_id = $2', [id, u.id]);
    if (!r.rowCount) throw new NotFoundException();
  }

  @Get(':id/availability') @UseGuards(AuthGuard)
  async availability(@CurrentUser() u: AuthUser, @Param('id') id: string) {
    await this.owned(u, id);
    const rules = (await this.db.query(
      `select day_of_week, to_char(start_time,'HH24:MI') as start, to_char(end_time,'HH24:MI') as "end"
       from availability_rules where listing_id = $1 order by day_of_week, start_time`, [id])).rows;
    const blocks = (await this.db.query(
      `select id, start_datetime, end_datetime, reason from availability_blocks
       where listing_id = $1 and end_datetime > now() order by start_datetime`, [id])).rows;
    return { always: rules.length === 0, rules, blocks };
  }

  @Put(':id/availability') @UseGuards(AuthGuard)
  async setAvailability(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body() d: AvailabilityDto) {
    await this.owned(u, id);
    const rules = d.always ? [] : d.rules ?? [];
    if (!d.always && rules.length === 0) throw new BadRequestException('Add at least one opening window, or choose always available');
    for (const r of rules) if (r.end !== '24:00' && r.end <= r.start) throw new BadRequestException('Each window must end after it starts');
    await this.db.tx(async (c) => {
      await c.query('delete from availability_rules where listing_id = $1', [id]);
      for (const r of rules) {
        await c.query('insert into availability_rules (listing_id, day_of_week, start_time, end_time) values ($1,$2,$3,$4)',
          [id, r.dayOfWeek, r.start, r.end]);
      }
    });
    return { ok: true };
  }

  @Post(':id/blocks') @UseGuards(AuthGuard)
  async addBlock(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body() d: BlockDto) {
    await this.owned(u, id);
    const s = new Date(d.start), e = new Date(d.end);
    if (isNaN(+s) || isNaN(+e) || !(e > s)) throw new BadRequestException('Invalid block times');
    const clash = await this.db.query(
      `select 1 from bookings where listing_id = $1 and status in ('confirmed','parked','overstay','requested')
       and tstzrange(booked_start, blocked_end) && tstzrange($2, $3)`, [id, s, e]);
    if (clash.rowCount) throw new ConflictException('That time already has a booking. Cancel it first if you need the space.');
    return (await this.db.query(
      `insert into availability_blocks (listing_id, start_datetime, end_datetime, reason) values ($1,$2,$3,$4) returning *`,
      [id, s, e, d.reason ?? null])).rows[0];
  }

  @Delete(':id/blocks/:blockId') @UseGuards(AuthGuard)
  async removeBlock(@CurrentUser() u: AuthUser, @Param('id') id: string, @Param('blockId') blockId: string) {
    await this.owned(u, id);
    await this.db.query('delete from availability_blocks where id = $1 and listing_id = $2', [blockId, id]);
    return { ok: true };
  }

  @Get(':id/extras') @UseGuards(AuthGuard)
  async listExtras(@CurrentUser() u: AuthUser, @Param('id') id: string) {
    await this.owned(u, id);
    return (await this.db.query(
      `select le.id, le.extra_type_id, et.name, le.price, le.price_unit, le.details, le.active
       from listing_extras le join extra_types et on et.id = le.extra_type_id where le.listing_id = $1`, [id])).rows;
  }

  @Put(':id/extras') @UseGuards(AuthGuard)
  async setExtras(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body() d: ExtrasDto) {
    await this.owned(u, id);
    const types = (await this.db.query('select id, allowed_price_units from extra_types where active')).rows;
    for (const e of d.extras) {
      const t = types.find((x) => x.id === e.extraTypeId);
      if (!t) throw new BadRequestException('Unknown extra type');
      if (!t.allowed_price_units.includes(e.priceUnit)) throw new BadRequestException(`That extra cannot be priced ${e.priceUnit.replace('_', ' ')}`);
    }
    // Keep ids stable for extras already on past bookings: upsert by (listing, type), deactivate the rest.
    await this.db.tx(async (c) => {
      await c.query('update listing_extras set active = false where listing_id = $1', [id]);
      for (const e of d.extras) {
        const ex = await c.query('select id from listing_extras where listing_id = $1 and extra_type_id = $2 order by active desc limit 1', [id, e.extraTypeId]);
        if (ex.rowCount) {
          await c.query('update listing_extras set price = $2, price_unit = $3, details = $4, active = $5 where id = $1',
            [ex.rows[0].id, e.price, e.priceUnit, e.details ?? null, e.active !== false]);
        } else {
          await c.query('insert into listing_extras (listing_id, extra_type_id, price, price_unit, details, active) values ($1,$2,$3,$4,$5,$6)',
            [id, e.extraTypeId, e.price, e.priceUnit, e.details ?? null, e.active !== false]);
        }
      }
    });
    return { ok: true };
  }
}
