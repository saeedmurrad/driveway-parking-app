import { Module } from '@nestjs/common';
import { BookingsModule } from '../bookings/bookings.module';
import { SettingsModule } from '../settings/settings.module';
import { ListingsController } from './listings.controller';

@Module({ imports: [BookingsModule, SettingsModule], controllers: [ListingsController] })
export class ListingsModule {}
