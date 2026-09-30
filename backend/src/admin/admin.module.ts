import { Module } from '@nestjs/common';
import { BookingsModule } from '../bookings/bookings.module';
import { DisputesModule } from '../disputes/disputes.module';
import { AdminController } from './admin.controller';

@Module({ imports: [BookingsModule, DisputesModule], controllers: [AdminController] })
export class AdminModule {}
