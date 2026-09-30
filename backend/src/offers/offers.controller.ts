import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { IsDateString, IsIn, IsNumber, IsOptional, IsString, IsUUID, MaxLength, Min } from 'class-validator';
import { AuthGuard, CurrentUser } from '../auth/auth.guard';
import { AuthUser } from '../auth/auth.service';
import { OffersService } from './offers.service';

class CreateOfferDto {
  @IsUUID() listingId: string;
  @IsOptional() @IsUUID() vehicleId?: string;
  @IsDateString() start: string;
  @IsDateString() end: string;
  @IsNumber() @Min(0.01) amount: number;
  @IsOptional() @IsString() @MaxLength(200) message?: string;
}
class RespondDto {
  @IsIn(['accept', 'decline', 'counter']) action: 'accept' | 'decline' | 'counter';
  @IsOptional() @IsNumber() amount?: number;
  @IsOptional() @IsString() @MaxLength(200) message?: string;
}

@Controller('offers')
@UseGuards(AuthGuard)
export class OffersController {
  constructor(private readonly svc: OffersService) {}

  @Get() mine(@CurrentUser() u: AuthUser) { return this.svc.mine(u.id); }
  @Post() create(@CurrentUser() u: AuthUser, @Body() d: CreateOfferDto) { return this.svc.create(u.id, d); }
  @Get(':threadId') thread(@CurrentUser() u: AuthUser, @Param('threadId') t: string) { return this.svc.thread(u.id, t); }
  @Post(':id/respond') respond(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body() d: RespondDto) { return this.svc.respond(u.id, id, d.action, d.amount, d.message); }
  @Post(':id/pay') pay(@CurrentUser() u: AuthUser, @Param('id') id: string) { return this.svc.pay(u.id, id); }
}
