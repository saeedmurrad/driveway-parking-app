import { Body, Controller, Get, Param, Post } from '@nestjs/common';
import { IsDateString, IsOptional, IsUUID } from 'class-validator';
import { BookingsService } from './bookings.service';

class CreateBookingDto {
  @IsUUID() listingId: string;
  @IsUUID() driverId: string; // POC: replace with the authenticated user (Supabase JWT)
  @IsOptional() @IsUUID() vehicleId?: string;
  @IsDateString() start: string;
  @IsDateString() end: string;
}

class ParkedDto {
  @IsUUID() driverId: string;
  @IsOptional() latitude?: number;
  @IsOptional() longitude?: number;
}

@Controller('bookings')
export class BookingsController {
  constructor(private readonly svc: BookingsService) {}

  @Post() create(@Body() dto: CreateBookingDto) { return this.svc.create(dto); }
  @Get(':id') one(@Param('id') id: string) { return this.svc.get(id); }
  @Post(':id/parked') parked(@Param('id') id: string, @Body() dto: ParkedDto) { return this.svc.markParked(id, dto); }
  @Post(':id/end') end(@Param('id') id: string, @Body() dto: ParkedDto) { return this.svc.end(id, dto.driverId); }
}
