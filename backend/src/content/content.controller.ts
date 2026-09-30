import { Controller, Get, Module, NotFoundException, Param } from '@nestjs/common';
import { DbService } from '../db/db.service';

@Controller('content')
export class ContentController {
  constructor(private readonly db: DbService) {}

  @Get() async all() {
    return (await this.db.query('select key, title, version from content order by key')).rows;
  }

  @Get(':key') async one(@Param('key') key: string) {
    const r = (await this.db.query('select key, title, body, version, updated_at from content where key = $1', [key])).rows[0];
    if (!r) throw new NotFoundException();
    return r;
  }
}

@Module({ controllers: [ContentController] })
export class ContentModule {}
