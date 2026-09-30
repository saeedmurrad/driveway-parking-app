import { BadRequestException, Body, Controller, ForbiddenException, Get, NotFoundException, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { ArrayMaxSize, IsArray, IsIn, IsNumber, IsOptional, IsString, Max, Min, MinLength } from 'class-validator';
import { DbService } from '../db/db.service';
import { AuthUser } from '../auth/auth.service';
import { AuthGuard, CurrentUser } from '../auth/auth.guard';
import { BookingsService } from '../bookings/bookings.service';
import { calculatePrice } from '../bookings/pricing';
import { SettingsService } from '../settings/settings.service';

class CreateListingDto {
  @IsString() @MinLength(3) title: string;
  @IsString() @MinLength(3) address: string;
  @IsOptional() @IsString() postcode?: string;
  @IsNumber() @Min(-90) @Max(90) latitude: number;
  @IsNumber() @Min(-180) @Max(180) longitude: number;
  @IsIn(['driveway', 'garage', 'bay', 'forecourt']) spaceType: string;
  @IsIn(['small', 'medium', 'large', 'van']) maxVehicleSize: string;
  @IsNumber() @Min(0.5) @Max(100) priceHour: number;
  @IsOptional() @IsNumber() @Min(1) priceDay?: number;
  @IsOptional() @IsArray() @ArrayMaxSize(10) features?: string[];
  @IsOptional() @IsString() accessInstructions?: string;
  @IsIn(['flexible', 'moderate', 'strict']) cancellationPolicy: string;
}

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
  async one(@Param('id') id: string, @Query('start') start?: string, @Query('end') end?: string) {
    const { rows } = await this.db.query(
      `select l.id, l.title, l.latitude, l.longitude, l.postcode, l.space_type, l.max_vehicle_size, l.features,
              l.price_hour, l.price_day, l.cancellation_policy, l.booking_mode, l.rating, l.status,
              split_part(u.name,' ',1) as host_name,
              (select count(*) from reviews r where r.listing_id = l.id)::int as review_count
       from listings l join users u on u.id = l.host_id where l.id = $1 and l.status in ('live','paused')`, [id]);
    if (!rows[0]) throw new NotFoundException();
    const reviews = (await this.db.query(
      `select r.stars, r.comment, r.created_at, split_part(u.name,' ',1) as name
       from reviews r join users u on u.id = r.from_user_id where r.listing_id = $1 order by r.created_at desc limit 5`, [id])).rows;
    const out: any = { ...rows[0], reviews };
    if (start && end) out.quote = await this.bookings.quote(id, new Date(start), new Date(end));
    return out;
  }

  @Post() @UseGuards(AuthGuard)
  async create(@CurrentUser() u: AuthUser, @Body() d: CreateListingDto) {
    if (!u.isHost) throw new ForbiddenException('Switch to a host account first');
    const { rows } = await this.db.query(
      `insert into listings (host_id, title, address, postcode, latitude, longitude, space_type, max_vehicle_size,
         features, access_instructions, price_hour, price_day, cancellation_policy, status)
       values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,'pending_approval') returning *`,
      [u.id, d.title, d.address, d.postcode ?? null, d.latitude, d.longitude, d.spaceType, d.maxVehicleSize,
       d.features ?? [], d.accessInstructions ?? null, d.priceHour, d.priceDay ?? null, d.cancellationPolicy]);
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
}
