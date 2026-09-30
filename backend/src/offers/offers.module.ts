import { Module } from '@nestjs/common';
import { BookingsModule } from '../bookings/bookings.module';
import { SettingsModule } from '../settings/settings.module';
import { OffersController } from './offers.controller';
import { OffersService } from './offers.service';

@Module({ imports: [BookingsModule, SettingsModule], controllers: [OffersController], providers: [OffersService] })
export class OffersModule {}
