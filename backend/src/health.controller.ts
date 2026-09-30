import { Controller, Get } from '@nestjs/common';
import { DbService } from './db/db.service';

@Controller('health')
export class HealthController {
  constructor(private readonly db: DbService) {}

  @Get()
  async health() {
    const { rows } = await this.db.query('select now() as now');
    return { status: 'ok', dbTime: rows[0].now };
  }
}
