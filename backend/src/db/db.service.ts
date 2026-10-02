import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { Pool, PoolClient, QueryResult } from 'pg';
import { describeDatabaseUrl, normalizeDatabaseUrl } from './database-url';

const DB_URL = normalizeDatabaseUrl(process.env.DATABASE_URL);
new Logger('Db').log(`Connecting with ${describeDatabaseUrl(DB_URL)}`);

@Injectable()
export class DbService implements OnModuleDestroy {
  private readonly pool = new Pool({
    connectionString: DB_URL,
    ssl:
      process.env.DATABASE_SSL === 'false' || DB_URL?.includes('localhost')
        ? false
        : { rejectUnauthorized: false },
    max: 5,
  });

  query(text: string, params: unknown[] = []): Promise<QueryResult> {
    return this.pool.query(text, params);
  }

  async tx<T>(fn: (c: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    try {
      await client.query('begin');
      const out = await fn(client);
      await client.query('commit');
      return out;
    } catch (e) {
      await client.query('rollback');
      throw e;
    } finally {
      client.release();
    }
  }

  onModuleDestroy() {
    return this.pool.end();
  }
}
