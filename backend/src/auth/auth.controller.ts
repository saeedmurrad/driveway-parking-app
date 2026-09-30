import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { IsBoolean, IsEmail, IsOptional, IsString, Length, MinLength } from 'class-validator';
import { AuthService, AuthUser } from './auth.service';
import { AuthGuard, CurrentUser } from './auth.guard';

class RegisterDto {
  @IsString() @MinLength(2) name: string;
  @IsEmail() email: string;
  @IsString() @MinLength(6) password: string;
  @IsOptional() @IsBoolean() isHost?: boolean;
  @IsBoolean() acceptTerms: boolean;
}
class LoginDto {
  @IsEmail() email: string;
  @IsString() password: string;
}
class ForgotDto { @IsEmail() email: string; }
class ResetDto {
  @IsEmail() email: string;
  @IsString() @Length(6, 6) code: string;
  @IsString() @MinLength(6) password: string;
}

@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post('register') register(@Body() d: RegisterDto) { return this.auth.register(d.name, d.email, d.password, !!d.isHost, d.acceptTerms); }
  @Post('login') login(@Body() d: LoginDto) { return this.auth.login(d.email, d.password); }
  @Post('forgot') forgot(@Body() d: ForgotDto) { return this.auth.forgot(d.email); }
  @Post('reset') reset(@Body() d: ResetDto) { return this.auth.reset(d.email, d.code, d.password); }
  @Get('me') @UseGuards(AuthGuard) me(@CurrentUser() u: AuthUser) { return this.auth.refresh(u.id); }
}
