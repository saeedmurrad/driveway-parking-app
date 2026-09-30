import { CanActivate, ExecutionContext, ForbiddenException, Injectable, UnauthorizedException, createParamDecorator } from '@nestjs/common';
import { AuthService, AuthUser } from './auth.service';

@Injectable()
export class AuthGuard implements CanActivate {
  constructor(protected readonly auth: AuthService) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const req = ctx.switchToHttp().getRequest();
    const h: string | undefined = req.headers.authorization;
    const user = h?.startsWith('Bearer ') ? this.auth.verify(h.slice(7)) : null;
    if (!user) throw new UnauthorizedException();
    if (!(await this.auth.isActive(user.id))) throw new ForbiddenException('This account is suspended or deleted.');
    req.user = user;
    return true;
  }
}

@Injectable()
export class AdminGuard extends AuthGuard {
  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    await super.canActivate(ctx);
    if (!ctx.switchToHttp().getRequest().user.isAdmin) throw new ForbiddenException('Admins only');
    return true;
  }
}

export const CurrentUser = createParamDecorator(
  (_: unknown, ctx: ExecutionContext): AuthUser => ctx.switchToHttp().getRequest().user);
