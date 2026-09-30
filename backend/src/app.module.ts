import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { DbModule } from './db/db.module';
import { HealthController } from './health.controller';
import { SettingsModule } from './settings/settings.module';
import { ListingsModule } from './listings/listings.module';
import { BookingsModule } from './bookings/bookings.module';
import { AuthModule } from './auth/auth.module';
import { MeModule } from './me/me.module';
import { AdminModule } from './admin/admin.module';
import { AuditModule } from './audit/audit.service';
import { ChatModule } from './chat/chat.controller';
import { ContentModule } from './content/content.controller';
import { DisputesModule } from './disputes/disputes.controller';
import { ExtrasModule } from './extras/extras.module';
import { OffersModule } from './offers/offers.module';
import { NotificationsModule } from './notifications/notifications.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    DbModule,
    SettingsModule,
    ListingsModule,
    BookingsModule,
    AuthModule,
    MeModule,
    AdminModule,
    NotificationsModule,
    OffersModule,
    ExtrasModule,
    AuditModule,
    ChatModule,
    ContentModule,
    DisputesModule,
  ],
  controllers: [HealthController],
})
export class AppModule {}
