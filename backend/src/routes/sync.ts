import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { Config } from '../config.js';
import type { Deps } from '../deps.js';
import { Errors } from '../errors.js';
import type { SyncKind, SyncRow } from '../repositories/interfaces.js';
import { decryptString, sealForStorage } from '../services/crypto.js';
import { requireAuth } from './auth.js';

const MAX_ITEM_BYTES = 32_000;
const MAX_ITEMS = 5000;

const item = z
  .object({
    id: z.string().uuid(),
    updatedAt: z.string().datetime(),
    deleted: z.boolean(),
  })
  .passthrough()
  .refine((v) => JSON.stringify(v).length <= MAX_ITEM_BYTES, 'Élément trop volumineux.');

const preferences = z
  .object({ data: z.record(z.unknown()), updatedAt: z.string().datetime() })
  .refine((v) => JSON.stringify(v).length <= MAX_ITEM_BYTES, 'Préférences trop volumineuses.');

const pushBody = z.object({
  favorites: z.array(item).max(MAX_ITEMS).default([]),
  collections: z.array(item).max(MAX_ITEMS).default([]),
  trips: z.array(item).max(MAX_ITEMS).default([]),
  preferences: preferences.optional(),
});

const PREFS_ID = 'preferences';

export function registerSyncRoutes(app: FastifyInstance, config: Config, deps: Deps): void {
  const auth = requireAuth(config);

  const seal = (value: unknown) => sealForStorage(JSON.stringify(value), config.syncKey);
  const open = (row: SyncRow) => JSON.parse(decryptString(row.data, config.syncKey)) as Record<string, unknown>;

  app.get('/v1/sync/pull', { preHandler: auth }, async (request) => {
    const query = z.object({ since: z.string().datetime().optional() }).safeParse(request.query);
    if (!query.success) throw Errors.validation('Le paramètre since doit être une date ISO 8601.');
    const since = query.data.since ? new Date(query.data.since) : undefined;
    const userId = request.userId as string;
    const serverTime = deps.now().toISOString();

    const load = async (kind: SyncKind) => (await deps.sync.list(userId, kind, since)).map(open);
    const [favorites, collections, trips, prefRows] = await Promise.all([
      load('favorites'),
      load('collections'),
      load('trips'),
      deps.sync.list(userId, 'preferences', since),
    ]);
    const prefRow = prefRows[0];
    return {
      serverTime,
      favorites,
      collections,
      trips,
      preferences: prefRow ? { data: open(prefRow), updatedAt: prefRow.updatedAt.toISOString() } : null,
    };
  });

  app.post('/v1/sync/push', { preHandler: auth, bodyLimit: 4 * 1024 * 1024 }, async (request) => {
    const body = pushBody.safeParse(request.body);
    if (!body.success) throw Errors.validation(body.error.issues[0]?.message);
    const userId = request.userId as string;
    const applied = { favorites: 0, collections: 0, trips: 0, preferences: false };

    const apply = async (kind: 'favorites' | 'collections' | 'trips') => {
      for (const it of body.data[kind]) {
        const row: SyncRow = {
          id: it.id,
          updatedAt: new Date(it.updatedAt),
          deleted: it.deleted,
          data: seal(it),
        };
        if (await deps.sync.upsertIfNewer(userId, kind, row)) applied[kind]++;
      }
    };
    await apply('favorites');
    await apply('collections');
    await apply('trips');

    if (body.data.preferences) {
      const p = body.data.preferences;
      const row: SyncRow = {
        id: PREFS_ID,
        updatedAt: new Date(p.updatedAt),
        deleted: false,
        data: seal(p.data),
      };
      applied.preferences = await deps.sync.upsertIfNewer(userId, 'preferences', row);
    }
    return { serverTime: deps.now().toISOString(), applied };
  });
}
