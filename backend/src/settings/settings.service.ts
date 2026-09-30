import { Injectable } from '@nestjs/common';
import { DbService } from '../db/db.service';

/** Admin-tunable values live in the `settings` table, never hard-coded. */
@Injectable()
export class SettingsService {
  constructor(private readonly db: DbService) {}

  async get(key: string): Promise<string> {
    const { rows } = await this.db.query('select value from settings where key = $1', [key]);
    if (!rows[0]) throw new Error(`Missing setting: ${key}`);
    return rows[0].value;
  }

  async getNumber(key: string): Promise<number> {
    return Number(await this.get(key));
  }
}
