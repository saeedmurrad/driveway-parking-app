import { Injectable, Logger } from '@nestjs/common';
import { PoolClient } from 'pg';
import { DbService } from '../db/db.service';

export type Channel = 'push' | 'email' | 'sms';

/**
 * Every notification is stored (shown in the in-app bell). Delivery over the other channels is
 * stubbed to the log in this POC: swap `deliver` for FCM / SendGrid / Twilio.
 */
@Injectable()
export class NotificationsService {
  private readonly log = new Logger('Notify');
  constructor(private readonly db: DbService) {}

  async notify(
    userId: string, type: string, title: string, body: string,
    opts: { ref?: [string, string]; channels?: Channel[]; client?: PoolClient; dedupe?: boolean } = {},
  ) {
    const q = (t: string, p: unknown[]) => (opts.client ? opts.client.query(t, p) : this.db.query(t, p));
    const channels = opts.channels ?? ['push'];
    if (opts.dedupe && opts.ref) {
      const d = await q('select 1 from notifications where user_id = $1 and type = $2 and ref_id = $3', [userId, type, opts.ref[1]]);
      if (d.rowCount) return;
    }
    await q(
      `insert into notifications (user_id, type, title, body, ref_type, ref_id, channels) values ($1,$2,$3,$4,$5,$6,$7)`,
      [userId, type, title, body, opts.ref?.[0] ?? null, opts.ref?.[1] ?? null, channels]);
    for (const c of channels) this.log.log(`[${c}] -> ${userId.slice(0, 8)}: ${title}`);
  }

  async list(userId: string) {
    const rows = (await this.db.query(
      `select id, type, title, body, read, ref_type, ref_id, created_at from notifications
       where user_id = $1 order by created_at desc limit 50`, [userId])).rows;
    return { unread: rows.filter((r) => !r.read).length, items: rows };
  }

  async markAllRead(userId: string) {
    await this.db.query('update notifications set read = true where user_id = $1 and not read', [userId]);
    return { ok: true };
  }
}
