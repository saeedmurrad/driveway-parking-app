import { Controller, Get, ServiceUnavailableException } from '@nestjs/common';
import { DbService } from './db/db.service';

@Controller('health')
export class HealthController {
  constructor(private readonly db: DbService) {}

  /** Returns 503 with the (password-free) reason when the database is unreachable, so deploys are easy to diagnose. */
  @Get()
  async health() {
    try {
      const { rows } = await this.db.query('select now() as now');
      return { status: 'ok', dbTime: rows[0].now };
    } catch (e: any) {
      throw new ServiceUnavailableException({ status: 'db_unavailable', reason: String(e?.message ?? e).slice(0, 200) });
    }
  }
}
