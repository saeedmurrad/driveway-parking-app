import { BadRequestException, ConflictException, ForbiddenException, Injectable, Logger, UnauthorizedException } from '@nestjs/common';
import { createHmac, randomInt, timingSafeEqual } from 'crypto';
import { DbService } from '../db/db.service';

export interface AuthUser { id: string; isHost: boolean; isAdmin: boolean }

const SECRET = () => process.env.JWT_SECRET ?? 'dev-only-secret-change-me';
const b64 = (s: string) => Buffer.from(s).toString('base64url');
export const DEMO = () => process.env.DEMO_MODE === 'true';

/** Minimal HMAC-signed token (JWT-shaped). Passwords are hashed in Postgres with pgcrypto bcrypt. */
@Injectable()
export class AuthService {
  private readonly log = new Logger('Auth');
  private readonly activeCache = new Map<string, { ok: boolean; at: number }>();
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

  /** Suspended/deleted users lose access immediately (cached for 15s to spare the database). */
  async isActive(id: string): Promise<boolean> {
    const hit = this.activeCache.get(id);
    if (hit && Date.now() - hit.at < 15_000) return hit.ok;
    const r = await this.db.query(`select account_status from users where id = $1`, [id]);
    const ok = r.rows[0]?.account_status === 'active';
    this.activeCache.set(id, { ok, at: Date.now() });
    return ok;
  }
  forget(id: string) { this.activeCache.delete(id); }

  private pack(row: any, extra: Record<string, unknown> = {}) {
    const user = {
      id: row.id, name: row.name, email: row.email, phone: row.phone, isHost: row.is_host, isAdmin: row.is_admin,
      emailVerified: row.email_verified, phoneVerified: row.phone_verified, verificationStatus: row.verification_status,
    };
    return { token: this.sign({ id: row.id, isHost: row.is_host, isAdmin: row.is_admin }), user, ...extra };
  }

  /** Creates a 6-digit code. In DEMO_MODE it is also returned so the UI can show it (no real email/SMS provider). */
  async issueCode(userId: string, kind: 'email' | 'phone' | 'reset', target?: string) {
    const code = String(randomInt(100000, 1000000));
    await this.db.query(`update verification_codes set used = true where user_id = $1 and kind = $2 and not used`, [userId, kind]);
    await this.db.query(
      `insert into verification_codes (user_id, kind, code, target, expires_at) values ($1,$2,$3,$4, now() + interval '30 minutes')`,
      [userId, kind, code, target ?? null]);
    this.log.log(`[${kind === 'phone' ? 'sms' : 'email'}] ${kind} code for ${userId.slice(0, 8)}: ${DEMO() ? code : '******'}`);
    return DEMO() ? code : undefined;
  }

  async consumeCode(userId: string, kind: 'email' | 'phone' | 'reset', code: string) {
    const r = await this.db.query(
      `update verification_codes set used = true
       where id = (select id from verification_codes where user_id = $1 and kind = $2 and not used and expires_at > now()
                   order by created_at desc limit 1) and code = $3 returning target`, [userId, kind, code]);
    if (!r.rowCount) throw new BadRequestException('That code is wrong or has expired');
    return r.rows[0].target as string | null;
  }

  async register(name: string, email: string, password: string, isHost: boolean, acceptTerms: boolean) {
    if (!acceptTerms) throw new BadRequestException('Please accept the Terms & Conditions and Privacy Policy');
    const terms = (await this.db.query(`select version from content where key = 'terms'`)).rows[0]?.version ?? 1;
    try {
      const { rows } = await this.db.query(
        `insert into users (name, email, password_hash, is_host, verification_status, terms_version, terms_accepted_at)
         values ($1, lower($2), crypt($3, gen_salt('bf')), $4, 'pending', $5, now()) returning *`,
        [name, email, password, isHost, terms]);
      const devCode = await this.issueCode(rows[0].id, 'email');
      return this.pack(rows[0], { devEmailCode: devCode });
    } catch (e: any) {
      if (e.code === '23505') throw new ConflictException('That email is already registered');
      throw e;
    }
  }

  async login(email: string, password: string) {
    const { rows } = await this.db.query(
      `select * from users where email = lower($1) and password_hash = crypt($2, password_hash)
       and account_status in ('active','suspended')`, [email, password]);
    if (!rows[0]) throw new UnauthorizedException('Wrong email or password');
    if (rows[0].account_status === 'suspended') throw new ForbiddenException('This account has been suspended. Please contact support.');
    return this.pack(rows[0]);
  }

  async refresh(id: string) {
    const { rows } = await this.db.query('select * from users where id = $1', [id]);
    if (!rows[0]) throw new UnauthorizedException();
    return this.pack(rows[0]);
  }

  async forgot(email: string) {
    const { rows } = await this.db.query(`select id from users where email = lower($1) and account_status = 'active'`, [email]);
    // Same response whether or not the account exists (no user enumeration).
    const devCode = rows[0] ? await this.issueCode(rows[0].id, 'reset') : undefined;
    return { ok: true, devCode };
  }

  async reset(email: string, code: string, password: string) {
    const { rows } = await this.db.query(`select id from users where email = lower($1)`, [email]);
    if (!rows[0]) throw new BadRequestException('That code is wrong or has expired');
    await this.consumeCode(rows[0].id, 'reset', code);
    await this.db.query(`update users set password_hash = crypt($2, gen_salt('bf')) where id = $1`, [rows[0].id, password]);
    return { ok: true };
  }

  async assertVerified(userId: string) {
    const r = await this.db.query(`select email_verified, phone_verified from users where id = $1`, [userId]);
    if (!r.rows[0]?.email_verified || !r.rows[0]?.phone_verified) {
      throw new ForbiddenException('Please verify your email and phone number first (Profile → Verify your account).');
    }
  }
}
