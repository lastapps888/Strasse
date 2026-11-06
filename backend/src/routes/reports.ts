import { randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { Config } from '../config.js';
import type { Deps } from '../deps.js';
import { AppError, Errors } from '../errors.js';
import type { ReportRecord, VoteKind } from '../repositories/interfaces.js';
import { hashInstallId } from '../services/crypto.js';
import { findDuplicate, DUPLICATE_RADIUS_METERS } from '../services/dedupe.js';
import { computeExpiry, isExpired, REPORT_TYPES, shouldAutoHide } from '../services/expiry.js';
import { bboxAround, haversineMeters, isNullIsland, parseBbox } from '../services/geo.js';
import type { Bbox } from '../services/geo.js';
import { computeReliability } from '../services/reliability.js';
import type { IncidentCategory, TrafficIncident } from '../traffic/provider.js';
import { fetchIncidentsCached } from './traffic.js';

export const MAX_REPORTS_PER_HOUR = 20;
export const MAX_VOTES_PER_HOUR = 120;
const HOUR_SECONDS = 3600;
const EXTERNAL_RADIUS_METERS = 500;

const createBody = z.object({
  type: z.enum(REPORT_TYPES),
  lat: z.number().min(-90).max(90),
  lon: z.number().min(-180).max(180),
});

const UUID = z.string().uuid();
const INSTALL_ID = z.string().uuid();

/** Catégorie de signalement → catégorie d'incident externe correspondante. */
const EXTERNAL_CATEGORY: Record<string, IncidentCategory> = {
  accident: 'accident',
  roadwork: 'roadwork',
  slowdown: 'slowdown',
  closure: 'closure',
  danger: 'danger',
  obstacle: 'danger',
};

/** Représentation publique : sans hachage d'auteur, avec fiabilité calculée. */
export function toPublicReport(r: ReportRecord, now: Date, external: readonly TrafficIncident[] = []) {
  const wanted = EXTERNAL_CATEGORY[r.type];
  const corroborated =
    wanted !== undefined &&
    external.some(
      (e) => e.category === wanted && haversineMeters(r.lat, r.lon, e.lat, e.lon) <= EXTERNAL_RADIUS_METERS,
    );
  const status = r.status === 'active' && isExpired(r.expiresAt, now) ? 'expired' : r.status;
  return {
    id: r.id,
    type: r.type,
    lat: r.lat,
    lon: r.lon,
    createdAt: r.createdAt.toISOString(),
    expiresAt: r.expiresAt.toISOString(),
    status,
    confirmations: r.confirmations,
    rejections: r.rejections,
    reliability: computeReliability({
      createdAt: r.createdAt,
      expiresAt: r.expiresAt,
      now,
      confirmations: r.confirmations,
      rejections: r.rejections,
      externalCorroboration: corroborated,
    }),
  };
}

export function registerReportRoutes(app: FastifyInstance, config: Config, deps: Deps): void {
  /** Pseudonyme de l'installation ; l'identifiant brut n'est jamais stocké. */
  function voterHash(request: FastifyRequest): string {
    const parsed = INSTALL_ID.safeParse(request.headers['x-install-id']);
    if (!parsed.success) {
      throw new AppError(400, 'missing_install_id', 'L\'en-tête X-Install-Id (UUID) est obligatoire.');
    }
    return hashInstallId(parsed.data, config.serverSalt);
  }

  async function limit(key: string, max: number): Promise<void> {
    if ((await deps.counters.hit(key, HOUR_SECONDS)) > max) throw Errors.tooMany();
  }

  app.get('/v1/reports', async (request) => {
    const bbox = parseBbox((request.query as Record<string, unknown>).bbox);
    const now = deps.now();
    const [reports, external] = await Promise.all([
      deps.reports.listActiveInBbox(bbox, now),
      externalIncidents(bbox),
    ]);
    return { reports: reports.map((r) => toPublicReport(r, now, external)) };
  });

  /** Incidents externes pour la fiabilité ; une panne du fournisseur n'affecte pas les signalements. */
  async function externalIncidents(bbox: Bbox): Promise<TrafficIncident[]> {
    if (!deps.traffic.available) return [];
    try {
      return (await fetchIncidentsCached(deps, bbox)).incidents;
    } catch (err) {
      app.log.warn({ err: (err as Error).message }, 'trafic externe indisponible');
      return [];
    }
  }

  app.post('/v1/reports', async (request, reply) => {
    const voter = voterHash(request);
    const body = createBody.safeParse(request.body);
    if (!body.success) throw Errors.validation('Type ou coordonnées de signalement invalides.');
    const { type, lat, lon } = body.data;
    if (isNullIsland(lat, lon)) throw Errors.validation('Les coordonnées (0, 0) ne sont pas acceptées.');
    await limit(`report:${voter}`, MAX_REPORTS_PER_HOUR);

    const now = deps.now();
    const nearby = await deps.reports.listActiveInBbox(bboxAround(lat, lon, DUPLICATE_RADIUS_METERS * 2), now);
    const duplicate = findDuplicate(nearby, type, lat, lon, now);

    if (duplicate) {
      // Doublon : le signalement compte comme une confirmation, une seule par installation.
      if (duplicate.reporterHash !== voter) {
        const vote = await deps.reports.recordVote(duplicate.id, voter, 'confirm');
        if (vote === 'ok') applyVote(duplicate, 'confirm');
        await deps.reports.save(duplicate);
      }
      return reply.code(200).send(toPublicReport(duplicate, now));
    }

    const report: ReportRecord = {
      id: randomUUID(),
      type,
      lat,
      lon,
      createdAt: now,
      expiresAt: computeExpiry(type, now, 0),
      status: 'active',
      confirmations: 0,
      rejections: 0,
      reporterHash: voter,
    };
    await deps.reports.insert(report);
    return reply.code(201).send(toPublicReport(report, now));
  });

  function applyVote(r: ReportRecord, vote: VoteKind): void {
    if (vote === 'confirm') {
      r.confirmations += 1;
      r.expiresAt = computeExpiry(r.type, r.createdAt, r.confirmations);
    } else {
      r.rejections += 1;
    }
    if (shouldAutoHide(r.confirmations, r.rejections)) r.status = 'hidden';
  }

  async function vote(request: FastifyRequest, kind: VoteKind) {
    const voter = voterHash(request);
    const id = UUID.safeParse((request.params as { id?: string }).id);
    if (!id.success) throw new AppError(404, 'report_not_found', 'Signalement introuvable.');
    await limit(`vote:${voter}`, MAX_VOTES_PER_HOUR);

    const now = deps.now();
    const report = await deps.reports.get(id.data);
    if (!report) throw new AppError(404, 'report_not_found', 'Signalement introuvable.');
    if (report.status !== 'active' || isExpired(report.expiresAt, now)) {
      throw new AppError(410, 'report_expired', 'Ce signalement n\'est plus actif.');
    }
    if (report.reporterHash === voter) {
      throw Errors.conflict('already_voted', 'Vous avez déjà participé à ce signalement.');
    }
    if ((await deps.reports.recordVote(report.id, voter, kind)) === 'duplicate') {
      throw Errors.conflict('already_voted', 'Vous avez déjà voté pour ce signalement.');
    }
    applyVote(report, kind);
    await deps.reports.save(report);
    return toPublicReport(report, now);
  }

  app.post('/v1/reports/:id/confirm', async (request) => vote(request, 'confirm'));
  app.post('/v1/reports/:id/reject', async (request) => vote(request, 'reject'));
}
