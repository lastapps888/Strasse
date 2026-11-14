// Implémentation PostgreSQL / PostGIS des dépôts.
// ATTENTION : ce code n'a PAS été exécuté contre une vraie base (aucune instance disponible
// lors de l'écriture). Voir backend/README.md, section « Limites connues ».
import type { Pool } from 'pg';
import type { Bbox } from '../../services/geo.js';
import type { ReportType } from '../../services/expiry.js';
import type {
  RefreshTokenRecord,
  RefreshTokenRepository,
  ReportRecord,
  ReportRepository,
  ReportStatus,
  SyncKind,
  SyncRepository,
  SyncRow,
  UserRecord,
  UserRepository,
  VoteKind,
} from '../interfaces.js';

export class PgUserRepository implements UserRepository {
  constructor(private readonly pool: Pool) {}

  async create(u: UserRecord): Promise<void> {
    await this.pool.query(
      'INSERT INTO users (id, email, password_hash, created_at) VALUES ($1, $2, $3, $4)',
      [u.id, u.email, u.passwordHash, u.createdAt],
    );
  }
  async findByEmail(email: string): Promise<UserRecord | null> {
    const r = await this.pool.query('SELECT * FROM users WHERE email = $1', [email]);
    return r.rows[0] ? mapUser(r.rows[0]) : null;
  }
  async findById(id: string): Promise<UserRecord | null> {
    const r = await this.pool.query('SELECT * FROM users WHERE id = $1', [id]);
    return r.rows[0] ? mapUser(r.rows[0]) : null;
  }
  async delete(id: string): Promise<void> {
    await this.pool.query('DELETE FROM users WHERE id = $1', [id]);
  }
}

function mapUser(row: Record<string, unknown>): UserRecord {
  return {
    id: row.id as string,
    email: row.email as string,
    passwordHash: row.password_hash as string,
    createdAt: row.created_at as Date,
  };
}

export class PgRefreshTokenRepository implements RefreshTokenRepository {
  constructor(private readonly pool: Pool) {}

  async insert(t: RefreshTokenRecord): Promise<void> {
    await this.pool.query(
      'INSERT INTO refresh_tokens (token_hash, user_id, family_id, expires_at, revoked) VALUES ($1,$2,$3,$4,$5)',
      [t.tokenHash, t.userId, t.familyId, t.expiresAt, t.revoked],
    );
  }
  async findByHash(hash: string): Promise<RefreshTokenRecord | null> {
    const r = await this.pool.query('SELECT * FROM refresh_tokens WHERE token_hash = $1', [hash]);
    const row = r.rows[0];
    if (!row) return null;
    return {
      tokenHash: row.token_hash,
      userId: row.user_id,
      familyId: row.family_id,
      expiresAt: row.expires_at,
      revoked: row.revoked,
    };
  }
  async revoke(hash: string): Promise<void> {
    await this.pool.query('UPDATE refresh_tokens SET revoked = TRUE WHERE token_hash = $1', [hash]);
  }
  async revokeFamily(familyId: string): Promise<void> {
    await this.pool.query('UPDATE refresh_tokens SET revoked = TRUE WHERE family_id = $1', [familyId]);
  }
  async deleteByUser(userId: string): Promise<void> {
    await this.pool.query('DELETE FROM refresh_tokens WHERE user_id = $1', [userId]);
  }
}

export class PgSyncRepository implements SyncRepository {
  constructor(private readonly pool: Pool) {}

  async upsertIfNewer(userId: string, kind: SyncKind, row: SyncRow): Promise<boolean> {
    const r = await this.pool.query(
      `INSERT INTO sync_items (user_id, kind, id, data, updated_at, deleted)
       VALUES ($1,$2,$3,$4,$5,$6)
       ON CONFLICT (user_id, kind, id) DO UPDATE
         SET data = EXCLUDED.data, updated_at = EXCLUDED.updated_at, deleted = EXCLUDED.deleted
         WHERE sync_items.updated_at < EXCLUDED.updated_at
       RETURNING id`,
      [userId, kind, row.id, row.data, row.updatedAt, row.deleted],
    );
    return (r.rowCount ?? 0) > 0;
  }
  async list(userId: string, kind: SyncKind, since?: Date): Promise<SyncRow[]> {
    const r = since
      ? await this.pool.query(
          'SELECT id, data, updated_at, deleted FROM sync_items WHERE user_id=$1 AND kind=$2 AND updated_at > $3 ORDER BY updated_at',
          [userId, kind, since],
        )
      : await this.pool.query(
          'SELECT id, data, updated_at, deleted FROM sync_items WHERE user_id=$1 AND kind=$2 ORDER BY updated_at',
          [userId, kind],
        );
    return r.rows.map((x) => ({ id: x.id, data: x.data, updatedAt: x.updated_at, deleted: x.deleted }));
  }
  async deleteAllForUser(userId: string): Promise<void> {
    await this.pool.query('DELETE FROM sync_items WHERE user_id = $1', [userId]);
  }
}

function mapReport(row: Record<string, unknown>): ReportRecord {
  return {
    id: row.id as string,
    type: row.type as ReportType,
    lat: row.lat as number,
    lon: row.lon as number,
    createdAt: row.created_at as Date,
    expiresAt: row.expires_at as Date,
    status: row.status as ReportStatus,
    confirmations: row.confirmations as number,
    rejections: row.rejections as number,
    reporterHash: row.reporter_hash as string,
  };
}

export class PgReportRepository implements ReportRepository {
  constructor(private readonly pool: Pool) {}

  async insert(r: ReportRecord): Promise<void> {
    await this.pool.query(
      `INSERT INTO reports (id, type, lat, lon, geom, created_at, expires_at, status, confirmations, rejections, reporter_hash)
       VALUES ($1,$2,$3::float8,$4::float8, ST_SetSRID(ST_MakePoint($4::float8,$3::float8),4326)::geography, $5,$6,$7,$8,$9,$10)`,
      [r.id, r.type, r.lat, r.lon, r.createdAt, r.expiresAt, r.status, r.confirmations, r.rejections, r.reporterHash],
    );
  }
  async get(id: string): Promise<ReportRecord | null> {
    const r = await this.pool.query('SELECT * FROM reports WHERE id = $1', [id]);
    return r.rows[0] ? mapReport(r.rows[0]) : null;
  }
  async save(r: ReportRecord): Promise<void> {
    await this.pool.query(
      'UPDATE reports SET status=$2, confirmations=$3, rejections=$4, expires_at=$5 WHERE id=$1',
      [r.id, r.status, r.confirmations, r.rejections, r.expiresAt],
    );
  }
  async listActiveInBbox(b: Bbox, now: Date): Promise<ReportRecord[]> {
    const r = await this.pool.query(
      `SELECT * FROM reports
       WHERE status = 'active' AND expires_at > $5
         AND geom && ST_MakeEnvelope($1,$2,$3,$4,4326)::geography`,
      [b.minLon, b.minLat, b.maxLon, b.maxLat, now],
    );
    return r.rows.map(mapReport);
  }
  async listByStatus(status: ReportStatus, limit: number): Promise<ReportRecord[]> {
    const r = await this.pool.query(
      'SELECT * FROM reports WHERE status = $1 ORDER BY created_at DESC LIMIT $2',
      [status, limit],
    );
    return r.rows.map(mapReport);
  }
  async delete(id: string): Promise<void> {
    await this.pool.query('DELETE FROM reports WHERE id = $1', [id]);
  }
  async expireDue(now: Date): Promise<number> {
    const r = await this.pool.query(
      "UPDATE reports SET status = 'expired' WHERE status = 'active' AND expires_at <= $1",
      [now],
    );
    return r.rowCount ?? 0;
  }
  async purgeExpiredBefore(before: Date): Promise<number> {
    const r = await this.pool.query("DELETE FROM reports WHERE status = 'expired' AND expires_at < $1", [before]);
    return r.rowCount ?? 0;
  }
  async recordVote(reportId: string, voterHash: string, vote: VoteKind): Promise<'ok' | 'duplicate'> {
    const r = await this.pool.query(
      `INSERT INTO report_votes (report_id, voter_hash, vote) VALUES ($1,$2,$3)
       ON CONFLICT (report_id, voter_hash) DO NOTHING RETURNING report_id`,
      [reportId, voterHash, vote],
    );
    return (r.rowCount ?? 0) > 0 ? 'ok' : 'duplicate';
  }
}
