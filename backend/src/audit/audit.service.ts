import { Global, Injectable, Module } from '@nestjs/common';
import { PoolClient } from 'pg';
import { DbService } from '../db/db.service';

/** Every admin action is logged: who, what, when (spec s13). */
@Injectable()
export class AuditService {
  constructor(private readonly db: DbService) {}

  log(adminId: string, action: string, target: string | null, details: unknown = {}, client?: PoolClient) {
    const q = client ?? this.db;
    return q.query('insert into admin_audit_log (admin_id, action, target, details) values ($1,$2,$3,$4)',
      [adminId, action, target, JSON.stringify(details)]);
  }
}

@Global()
@Module({ providers: [AuditService], exports: [AuditService] })
export class AuditModule {}
