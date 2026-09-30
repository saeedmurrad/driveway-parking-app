import { Module } from '@nestjs/common';
import { SettingsModule } from '../settings/settings.module';
import { BookingsController } from './bookings.controller';
import { BookingsService } from './bookings.service';

@Module({ imports: [SettingsModule], controllers: [BookingsController], providers: [BookingsService] })
export class BookingsModule {}
