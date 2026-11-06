import type { Bbox } from '../../services/geo.js';
import type {
  AbuseCounter,
  KeyValueCache,
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

export class MemoryUserRepository implements UserRepository {
  private readonly users = new Map<string, UserRecord>();

  async create(user: UserRecord): Promise<void> {
    this.users.set(user.id, { ...user });
  }
  async findByEmail(email: string): Promise<UserRecord | null> {
    for (const u of this.users.values()) if (u.email === email) return { ...u };
    return null;
  }
  async findById(id: string): Promise<UserRecord | null> {
    const u = this.users.get(id);
    return u ? { ...u } : null;
  }
  async delete(id: string): Promise<void> {
    this.users.delete(id);
  }
  get size(): number {
    return this.users.size;
  }
}

export class MemoryRefreshTokenRepository implements RefreshTokenRepository {
  private readonly tokens = new Map<string, RefreshTokenRecord>();

  async insert(token: RefreshTokenRecord): Promise<void> {
    this.tokens.set(token.tokenHash, { ...token });
  }
  async findByHash(hash: string): Promise<RefreshTokenRecord | null> {
    const t = this.tokens.get(hash);
    return t ? { ...t } : null;
  }
  async revoke(hash: string): Promise<void> {
    const t = this.tokens.get(hash);
    if (t) t.revoked = true;
  }
  async revokeFamily(familyId: string): Promise<void> {
    for (const t of this.tokens.values()) if (t.familyId === familyId) t.revoked = true;
  }
  async deleteByUser(userId: string): Promise<void> {
    for (const [k, t] of this.tokens) if (t.userId === userId) this.tokens.delete(k);
  }
  countForUser(userId: string): number {
    let n = 0;
    for (const t of this.tokens.values()) if (t.userId === userId) n++;
    return n;
  }
}

export class MemorySyncRepository implements SyncRepository {
  private readonly rows = new Map<string, SyncRow>();

  private key(userId: string, kind: SyncKind, id: string): string {
    return `${userId}|${kind}|${id}`;
  }

  async upsertIfNewer(userId: string, kind: SyncKind, row: SyncRow): Promise<boolean> {
    const k = this.key(userId, kind, row.id);
    const existing = this.rows.get(k);
    if (existing && existing.updatedAt.getTime() >= row.updatedAt.getTime()) return false;
    this.rows.set(k, { ...row });
    return true;
  }
  async list(userId: string, kind: SyncKind, since?: Date): Promise<SyncRow[]> {
    const prefix = `${userId}|${kind}|`;
    const out: SyncRow[] = [];
    for (const [k, r] of this.rows) {
      if (!k.startsWith(prefix)) continue;
      if (since && r.updatedAt.getTime() <= since.getTime()) continue;
      out.push({ ...r });
    }
    return out.sort((a, b) => a.updatedAt.getTime() - b.updatedAt.getTime());
  }
  async deleteAllForUser(userId: string): Promise<void> {
    for (const k of [...this.rows.keys()]) if (k.startsWith(`${userId}|`)) this.rows.delete(k);
  }
  countForUser(userId: string): number {
    let n = 0;
    for (const k of this.rows.keys()) if (k.startsWith(`${userId}|`)) n++;
    return n;
  }
}

export class MemoryReportRepository implements ReportRepository {
  private readonly reports = new Map<string, ReportRecord>();
  private readonly votes = new Map<string, VoteKind>();

  async insert(report: ReportRecord): Promise<void> {
    this.reports.set(report.id, { ...report });
  }
  async get(id: string): Promise<ReportRecord | null> {
    const r = this.reports.get(id);
    return r ? { ...r } : null;
  }
  async save(report: ReportRecord): Promise<void> {
    if (this.reports.has(report.id)) this.reports.set(report.id, { ...report });
  }
  async listActiveInBbox(b: Bbox, now: Date): Promise<ReportRecord[]> {
    return [...this.reports.values()]
      .filter(
        (r) =>
          r.status === 'active' &&
          r.expiresAt.getTime() > now.getTime() &&
          r.lon >= b.minLon &&
          r.lon <= b.maxLon &&
          r.lat >= b.minLat &&
          r.lat <= b.maxLat,
      )
      .map((r) => ({ ...r }));
  }
  async listByStatus(status: ReportStatus, limit: number): Promise<ReportRecord[]> {
    return [...this.reports.values()]
      .filter((r) => r.status === status)
      .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())
      .slice(0, limit)
      .map((r) => ({ ...r }));
  }
  async delete(id: string): Promise<void> {
    this.reports.delete(id);
    for (const k of [...this.votes.keys()]) if (k.startsWith(`${id}|`)) this.votes.delete(k);
  }
  async expireDue(now: Date): Promise<number> {
    let n = 0;
    for (const r of this.reports.values()) {
      if (r.status === 'active' && r.expiresAt.getTime() <= now.getTime()) {
        r.status = 'expired';
        n++;
      }
    }
    return n;
  }
  async purgeExpiredBefore(before: Date): Promise<number> {
    let n = 0;
    for (const [id, r] of [...this.reports]) {
      if (r.status === 'expired' && r.expiresAt.getTime() < before.getTime()) {
        await this.delete(id);
        n++;
      }
    }
    return n;
  }
  async recordVote(reportId: string, voterHash: string, vote: VoteKind): Promise<'ok' | 'duplicate'> {
    const k = `${reportId}|${voterHash}`;
    if (this.votes.has(k)) return 'duplicate';
    this.votes.set(k, vote);
    return 'ok';
  }
}

/** Compteurs en mémoire (développement, tests, ou absence de Redis). */
export class MemoryAbuseCounter implements AbuseCounter {
  private readonly buckets = new Map<string, { count: number; resetAt: number }>();

  constructor(private readonly now: () => Date = () => new Date()) {}

  async hit(key: string, windowSeconds: number): Promise<number> {
    const t = this.now().getTime();
    const b = this.buckets.get(key);
    if (!b || b.resetAt <= t) {
      this.buckets.set(key, { count: 1, resetAt: t + windowSeconds * 1000 });
      return 1;
    }
    b.count++;
    return b.count;
  }
}

export class MemoryCache implements KeyValueCache {
  private readonly entries = new Map<string, { value: string; expiresAt: number }>();

  constructor(private readonly now: () => Date = () => new Date()) {}

  async get(key: string): Promise<string | null> {
    const e = this.entries.get(key);
    if (!e) return null;
    if (e.expiresAt <= this.now().getTime()) {
      this.entries.delete(key);
      return null;
    }
    return e.value;
  }
  async set(key: string, value: string, ttlSeconds: number): Promise<void> {
    this.entries.set(key, { value, expiresAt: this.now().getTime() + ttlSeconds * 1000 });
  }
}
