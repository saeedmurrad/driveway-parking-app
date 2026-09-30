import { Controller, Get, UseGuards } from '@nestjs/common';
import { DbService } from '../db/db.service';
import { AuthGuard } from '../auth/auth.guard';

/** Admin-managed catalogue of paid extras (no app update needed to add a new type). */
@Controller('extra-types')
@UseGuards(AuthGuard)
export class ExtrasController {
  constructor(private readonly db: DbService) {}

  @Get() async list() {
    return (await this.db.query(
      'select id, name, description, allowed_price_units, ev_only from extra_types where active order by name')).rows;
  }
}
