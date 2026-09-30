import { ConflictException, Injectable, UnauthorizedException } from '@nestjs/common';
import { createHmac, timingSafeEqual } from 'crypto';
import { DbService } from '../db/db.service';

export interface AuthUser { id: string; isHost: boolean; isAdmin: boolean }

const SECRET = () => process.env.JWT_SECRET ?? 'dev-only-secret-change-me';
const b64 = (s: string) => Buffer.from(s).toString('base64url');

/** Minimal HMAC-signed token (JWT-shaped). Passwords are hashed in Postgres with pgcrypto bcrypt. */
@Injectable()
export class AuthService {
  constructor(private readonly db: DbService) {}

  sign(u: AuthUser): string {
    const body = b64(JSON.stringify({ ...u, exp: Date.now() + 7 * 24 * 3600_000 }));
    return `${body}.${createHmac('sha256', SECRET()).update(body).digest('base64url')}`;
  }

  verify(token: string): AuthUser | null {
    const [body, sig] = token.split('.');
    if (!body || !sig) return null;
    const expected = createHmac('sha256', SECRET()).update(body).digest('base64url');
    if (sig.length !== expected.length || !timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) return null;
    const p = JSON.parse(Buffer.from(body, 'base64url').toString());
    return p.exp > Date.now() ? { id: p.id, isHost: p.isHost, isAdmin: p.isAdmin } : null;
  }

  private pack(row: any) {
    const user = { id: row.id, name: row.name, email: row.email, isHost: row.is_host, isAdmin: row.is_admin };
    return { token: this.sign({ id: row.id, isHost: row.is_host, isAdmin: row.is_admin }), user };
  }

  async register(name: string, email: string, password: string, isHost: boolean) {
    try {
      const { rows } = await this.db.query(
        `insert into users (name, email, password_hash, is_host, verification_status)
         values ($1, lower($2), crypt($3, gen_salt('bf')), $4, 'verified') returning *`,
        [name, email, password, isHost]);
      return this.pack(rows[0]);
    } catch (e: any) {
      if (e.code === '23505') throw new ConflictException('That email is already registered');
      throw e;
    }
  }

  async login(email: string, password: string) {
    const { rows } = await this.db.query(
      `select * from users where email = lower($1) and password_hash = crypt($2, password_hash)
       and account_status = 'active'`, [email, password]);
    if (!rows[0]) throw new UnauthorizedException('Wrong email or password');
    return this.pack(rows[0]);
  }

  async refresh(id: string) {
    const { rows } = await this.db.query('select * from users where id = $1', [id]);
    if (!rows[0]) throw new UnauthorizedException();
    return this.pack(rows[0]);
  }
}
