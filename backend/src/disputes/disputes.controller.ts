import { Body, Controller, Module, Param, Post, UseGuards } from '@nestjs/common';
import { IsArray, IsIn, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';
import { AuthGuard, CurrentUser } from '../auth/auth.guard';
import { AuthUser } from '../auth/auth.service';
import { BookingsModule } from '../bookings/bookings.module';
import { BookingsService } from '../bookings/bookings.service';
import { DISPUTE_TYPES, DisputesService } from './disputes.service';

class DisputeDto {
  @IsIn(DISPUTE_TYPES) type: string;
  @IsOptional() @IsString() @MaxLength(1000) description?: string;
  @IsOptional() @IsUUID() extraId?: string;
  @IsOptional() @IsArray() photos?: string[];
}

@Controller('bookings/:id')
@UseGuards(AuthGuard)
export class DisputesController {
  constructor(private readonly svc: DisputesService, private readonly bookings: BookingsService) {}
  @Post('dispute') create(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body() d: DisputeDto) { return this.svc.create(u.id, id, d); }
  @Post('occupied-refund') occupied(@CurrentUser() u: AuthUser, @Param('id') id: string) { return this.bookings.occupiedRefund(u.id, id); }
}

@Module({ imports: [BookingsModule], controllers: [DisputesController], providers: [DisputesService], exports: [DisputesService] })
export class DisputesModule {}
