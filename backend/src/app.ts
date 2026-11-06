import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import Fastify, { type FastifyInstance } from 'fastify';
import { ZodError } from 'zod';
import type { Config } from './config.js';
import type { Deps } from './deps.js';
import { AppError } from './errors.js';
import { registerAdminRoutes } from './routes/admin.js';
import { registerAuthRoutes } from './routes/auth.js';
import { registerReportRoutes } from './routes/reports.js';
import { registerSyncRoutes } from './routes/sync.js';
import { registerTrafficRoutes } from './routes/traffic.js';

export const API_VERSION = '0.1.0';

/**
 * Construit l'application. Les dépendances (dépôts, horloge, cache…) sont injectées :
 * les tests utilisent les implémentations en mémoire.
 */
export async function buildApp(config: Config, deps: Deps): Promise<FastifyInstance> {
  const app = Fastify({
    // Journaux anonymisés : ni adresse IP, ni en-têtes d'identification, ni paramètres de requête.
    logger:
      config.NODE_ENV === 'test'
        ? false
        : {
            level: 'info',
            redact: {
              paths: [
                'req.headers.authorization',
                'req.headers["x-install-id"]',
                'req.headers["x-forwarded-for"]',
                'req.headers.cookie',
              ],
              remove: true,
            },
            serializers: {
              req: (req: { method: string; url: string }) => ({ method: req.method, url: req.url.split('?')[0] }),
              res: (res: { statusCode: number }) => ({ statusCode: res.statusCode }),
            },
          },
    trustProxy: true,
    bodyLimit: 256 * 1024,
  });

  await app.register(helmet);
  await app.register(cors, { origin: config.corsOrigins.length > 0 ? config.corsOrigins : false });
  await app.register(rateLimit, {
    max: config.RATE_LIMIT_MAX,
    timeWindow: '1 minute',
    // Retourner une Error : elle passe par le gestionnaire d'erreurs commun (format uniforme).
    errorResponseBuilder: () => new AppError(429, 'rate_limited', 'Trop de requêtes. Réessayez dans quelques instants.'),
  });

  app.setErrorHandler((error: Error & { statusCode?: number; code?: string }, request, reply) => {
    if (error instanceof AppError) {
      return reply.code(error.status).send({ error: { code: error.code, message: error.message } });
    }
    if (error instanceof ZodError) {
      return reply.code(400).send({ error: { code: 'validation_error', message: 'Les données envoyées sont invalides.' } });
    }
    const status = error.statusCode ?? 500;
    if (status >= 400 && status < 500) {
      const code = status === 413 ? 'payload_too_large' : 'bad_request';
      const message = status === 413 ? 'La requête est trop volumineuse.' : 'Requête invalide.';
      return reply.code(status).send({ error: { code, message } });
    }
    request.log.error({ err: error.message }, 'erreur interne');
    return reply.code(500).send({ error: { code: 'internal_error', message: 'Une erreur interne est survenue.' } });
  });

  app.setNotFoundHandler((_request, reply) =>
    reply.code(404).send({ error: { code: 'not_found', message: 'Ressource introuvable.' } }),
  );

  app.get('/v1/health', async () => ({
    status: 'ok',
    version: API_VERSION,
    time: deps.now().toISOString(),
  }));

  registerAuthRoutes(app, config, deps);
  registerSyncRoutes(app, config, deps);
  registerReportRoutes(app, config, deps);
  registerTrafficRoutes(app, deps);
  registerAdminRoutes(app, config, deps);

  // Maintenance : expiration automatique et purge des signalements anciens.
  if (config.NODE_ENV !== 'test') {
    const DAY_MS = 24 * 60 * 60 * 1000;
    const timer = setInterval(() => {
      const now = deps.now();
      deps.reports
        .expireDue(now)
        .then(() => deps.reports.purgeExpiredBefore(new Date(now.getTime() - 7 * DAY_MS)))
        .catch((err: Error) => app.log.warn({ err: err.message }, 'maintenance des signalements en échec'));
    }, config.MAINTENANCE_INTERVAL_SECONDS * 1000);
    timer.unref();
    app.addHook('onClose', async () => clearInterval(timer));
  }

  return app;
}
