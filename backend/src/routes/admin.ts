import { timingSafeEqual } from 'node:crypto';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { Config } from '../config.js';
import type { Deps } from '../deps.js';
import { AppError, Errors } from '../errors.js';
import { computeExpiry } from '../services/expiry.js';
import { toPublicReport } from './reports.js';

const listQuery = z.object({
  status: z.enum(['active', 'hidden', 'expired']).default('hidden'),
  limit: z.coerce.number().int().min(1).max(200).default(50),
});
const moderateBody = z.object({ action: z.enum(['hide', 'restore', 'delete']) });

function tokenMatches(provided: string, expected: string): boolean {
  const a = Buffer.from(provided);
  const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}

/** Routes de modération : absentes (404) si ADMIN_TOKEN n'est pas configuré. */
export function registerAdminRoutes(app: FastifyInstance, config: Config, deps: Deps): void {
  const adminToken = config.ADMIN_TOKEN;
  if (!adminToken) return;

  const guard = async (request: FastifyRequest): Promise<void> => {
    const header = request.headers.authorization;
    const provided = header?.startsWith('Bearer ') ? header.slice(7) : '';
    if (!provided || !tokenMatches(provided, adminToken)) throw Errors.unauthorized('Jeton d\'administration invalide.');
  };

  app.get('/v1/admin/reports', { preHandler: guard }, async (request) => {
    const q = listQuery.safeParse(request.query);
    if (!q.success) throw Errors.validation('Paramètres de liste invalides.');
    const now = deps.now();
    const rows = await deps.reports.listByStatus(q.data.status, q.data.limit);
    return { reports: rows.map((r) => toPublicReport(r, now)) };
  });

  app.post('/v1/admin/reports/:id/moderate', { preHandler: guard }, async (request, reply) => {
    const body = moderateBody.safeParse(request.body);
    if (!body.success) throw Errors.validation('Action de modération invalide.');
    const id = (request.params as { id: string }).id;
    const report = await deps.reports.get(id);
    if (!report) throw new AppError(404, 'report_not_found', 'Signalement introuvable.');
    const now = deps.now();

    if (body.data.action === 'delete') {
      await deps.reports.delete(id);
      return reply.code(204).send();
    }
    if (body.data.action === 'hide') {
      report.status = 'hidden';
    } else {
      // Restauration : actif si encore valide, sinon expiré.
      report.expiresAt = report.expiresAt.getTime() > now.getTime()
        ? report.expiresAt
        : computeExpiry(report.type, now, 0);
      report.status = 'active';
    }
    await deps.reports.save(report);
    return toPublicReport(report, now);
  });
}
