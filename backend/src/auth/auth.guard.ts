import { CanActivate, ExecutionContext, ForbiddenException, Injectable, UnauthorizedException, createParamDecorator } from '@nestjs/common';
import { AuthService, AuthUser } from './auth.service';

@Injectable()
export class AuthGuard implements CanActivate {
  constructor(protected readonly auth: AuthService) {}

  canActivate(ctx: ExecutionContext): boolean {
    const req = ctx.switchToHttp().getRequest();
    const h: string | undefined = req.headers.authorization;
    const user = h?.startsWith('Bearer ') ? this.auth.verify(h.slice(7)) : null;
    if (!user) throw new UnauthorizedException();
    req.user = user;
    return true;
  }
}

@Injectable()
export class AdminGuard extends AuthGuard {
  canActivate(ctx: ExecutionContext): boolean {
    super.canActivate(ctx);
    if (!ctx.switchToHttp().getRequest().user.isAdmin) throw new ForbiddenException('Admins only');
    return true;
  }
}

export const CurrentUser = createParamDecorator(
  (_: unknown, ctx: ExecutionContext): AuthUser => ctx.switchToHttp().getRequest().user);
