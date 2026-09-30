import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { Type } from 'class-transformer';
import { IsArray, IsBoolean, IsDateString, ValidateNested, IsInt, IsNumber, IsOptional, IsString, IsUUID, Max, Min } from 'class-validator';
import { AuthUser } from '../auth/auth.service';
import { AuthGuard, CurrentUser } from '../auth/auth.guard';
import { BookingsService } from './bookings.service';

class ExtraDto { @IsUUID() id: string; @IsOptional() @IsInt() @Min(1) @Max(200) quantity?: number; }
class CreateBookingDto {
  @IsUUID() listingId: string;
  @IsOptional() @IsUUID() vehicleId?: string;
  @IsDateString() start: string;
  @IsDateString() end: string;
  @IsOptional() @IsArray() @ValidateNested({ each: true }) @Type(() => ExtraDto) extras?: ExtraDto[];
}
class GeoDto {
  @IsOptional() @IsNumber() latitude?: number;
  @IsOptional() @IsNumber() longitude?: number;
  @IsOptional() @IsString() photoUrl?: string;
}
class RespondDto { @IsBoolean() accept: boolean; }
class ExtendDto { @IsInt() @Min(1) @Max(24) hours: number; }
class CarDto { @IsBoolean() stillThere: boolean; }
class ReviewDto {
  @IsInt() @Min(1) @Max(5) stars: number;
  @IsOptional() @IsString() comment?: string;
}

@Controller('bookings')
@UseGuards(AuthGuard)
export class BookingsController {
  constructor(private readonly svc: BookingsService) {}

  @Post() create(@CurrentUser() u: AuthUser, @Body() d: CreateBookingDto) { return this.svc.create(u.id, d); }
  @Get(':id') one(@CurrentUser() u: AuthUser, @Param('id') id: string) { return this.svc.detail(u.id, id); }
  @Get(':id/receipt') receipt(@CurrentUser() u: AuthUser, @Param('id') id: string) { return this.svc.receipt(u.id, id); }
  @Post(':id/pay') pay(@CurrentUser() u: AuthUser, @Param('id') id: string) { return this.svc.pay(u.id, id); }
  @Post(':id/parked') parked(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body() g: GeoDto) { return this.svc.markParked(u.id, id, g); }
  @Post(':id/end') end(@CurrentUser() u: AuthUser, @Param('id') id: string) { return this.svc.end(u.id, id); }
  @Post(':id/cancel') cancel(@CurrentUser() u: AuthUser, @Param('id') id: string) { return this.svc.cancel(u.id, id); }
  @Post(':id/respond') respond(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body() d: RespondDto) { return this.svc.respond(u.id, id, d.accept); }
  @Post(':id/extend') extend(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body() d: ExtendDto) { return this.svc.extend(u.id, id, d.hours); }
  @Post(':id/car-status') car(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body() d: CarDto) { return this.svc.carStatus(u.id, id, d.stillThere); }
  @Post(':id/review') review(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body() d: ReviewDto) { return this.svc.review(u.id, id, d.stars, d.comment); }
}
