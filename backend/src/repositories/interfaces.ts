import type { Bbox } from '../services/geo.js';
import type { ReportType } from '../services/expiry.js';

export type ReportStatus = 'active' | 'hidden' | 'expired';
export type VoteKind = 'confirm' | 'reject';
export type SyncKind = 'favorites' | 'collections' | 'trips' | 'preferences';

export interface UserRecord {
  id: string;
  email: string;
  passwordHash: string;
  createdAt: Date;
}

export interface RefreshTokenRecord {
  tokenHash: string;
  userId: string;
  familyId: string;
  expiresAt: Date;
  revoked: boolean;
}

/** Ligne de synchronisation : `data` est le JSON de l'élément, éventuellement chiffré. */
export interface SyncRow {
  id: string;
  updatedAt: Date;
  deleted: boolean;
  data: string;
}

export interface ReportRecord {
  id: string;
  type: ReportType;
  lat: number;
  lon: number;
  createdAt: Date;
  expiresAt: Date;
  status: ReportStatus;
  confirmations: number;
  rejections: number;
  /** Pseudonyme HMAC de l'installation auteure ; jamais exposé publiquement. */
  reporterHash: string;
}

export interface UserRepository {
  create(user: UserRecord): Promise<void>;
  findByEmail(email: string): Promise<UserRecord | null>;
  findById(id: string): Promise<UserRecord | null>;
  delete(id: string): Promise<void>;
}

export interface RefreshTokenRepository {
  insert(token: RefreshTokenRecord): Promise<void>;
  findByHash(hash: string): Promise<RefreshTokenRecord | null>;
  revoke(hash: string): Promise<void>;
  revokeFamily(familyId: string): Promise<void>;
  deleteByUser(userId: string): Promise<void>;
}

export interface SyncRepository {
  /** Insère ou remplace si `row.updatedAt` est strictement plus récent. Retourne true si appliqué. */
  upsertIfNewer(userId: string, kind: SyncKind, row: SyncRow): Promise<boolean>;
  list(userId: string, kind: SyncKind, since?: Date): Promise<SyncRow[]>;
  deleteAllForUser(userId: string): Promise<void>;
}

export interface ReportRepository {
  insert(report: ReportRecord): Promise<void>;
  get(id: string): Promise<ReportRecord | null>;
  /** Met à jour les champs modifiables (statut, compteurs, expiration). */
  save(report: ReportRecord): Promise<void>;
  /** Signalements actifs et non expirés dans la zone. */
  listActiveInBbox(bbox: Bbox, now: Date): Promise<ReportRecord[]>;
  listByStatus(status: ReportStatus, limit: number): Promise<ReportRecord[]>;
  delete(id: string): Promise<void>;
  /** Passe en « expired » les signalements actifs dont l'échéance est atteinte. */
  expireDue(now: Date): Promise<number>;
  /** Supprime les signalements expirés avant `before`. */
  purgeExpiredBefore(before: Date): Promise<number>;
  /** Enregistre un vote ; « duplicate » si cette installation a déjà voté. */
  recordVote(reportId: string, voterHash: string, vote: VoteKind): Promise<'ok' | 'duplicate'>;
}

/** Compteur à fenêtre fixe, pour la limitation par installation. */
export interface AbuseCounter {
  hit(key: string, windowSeconds: number): Promise<number>;
}

/** Cache clé/valeur à durée de vie courte. */
export interface KeyValueCache {
  get(key: string): Promise<string | null>;
  set(key: string, value: string, ttlSeconds: number): Promise<void>;
}
