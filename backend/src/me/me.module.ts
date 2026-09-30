import { Module } from '@nestjs/common';
import { BookingsModule } from '../bookings/bookings.module';
import { SettingsModule } from '../settings/settings.module';
import { MeController } from './me.controller';

@Module({ imports: [BookingsModule, SettingsModule], controllers: [MeController] })
export class MeModule {}
