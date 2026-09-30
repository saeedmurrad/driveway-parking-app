import { Module } from '@nestjs/common';
import { SettingsModule } from '../settings/settings.module';
import { BookingsController } from './bookings.controller';
import { BookingsService } from './bookings.service';
import { SchedulerService } from './scheduler.service';

@Module({
  imports: [SettingsModule],
  controllers: [BookingsController],
  providers: [BookingsService, SchedulerService],
  exports: [BookingsService],
})
export class BookingsModule {}
