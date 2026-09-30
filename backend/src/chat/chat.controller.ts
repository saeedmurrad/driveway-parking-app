import { Body, Controller, Get, Module, Param, Post, UseGuards } from '@nestjs/common';
import { IsString, MaxLength } from 'class-validator';
import { AuthGuard, CurrentUser } from '../auth/auth.guard';
import { AuthUser } from '../auth/auth.service';
import { ChatService } from './chat.service';

class MessageDto { @IsString() @MaxLength(1000) text: string; }

@Controller('bookings/:id/messages')
@UseGuards(AuthGuard)
export class ChatController {
  constructor(private readonly svc: ChatService) {}
  @Get() list(@CurrentUser() u: AuthUser, @Param('id') id: string) { return this.svc.list(u.id, id); }
  @Post() send(@CurrentUser() u: AuthUser, @Param('id') id: string, @Body() d: MessageDto) { return this.svc.send(u.id, id, d.text); }
}

@Module({ controllers: [ChatController], providers: [ChatService] })
export class ChatModule {}
