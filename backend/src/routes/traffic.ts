import type { FastifyInstance } from 'fastify';
import type { Deps } from '../deps.js';
import { bboxCacheKey, parseBbox } from '../services/geo.js';
import type { Bbox } from '../services/geo.js';
import type { TrafficIncident } from '../traffic/provider.js';

const CACHE_TTL_SECONDS = 60;

interface Cached {
  incidents: TrafficIncident[];
  fetchedAt: string;
}

/** Incidents du fournisseur actif, mis en cache 60 s par zone arrondie (Redis ou mémoire). */
export async function fetchIncidentsCached(deps: Deps, bbox: Bbox): Promise<Cached> {
  const key = `traffic:${deps.traffic.name}:${bboxCacheKey(bbox)}`;
  const hit = await deps.cache.get(key);
  if (hit) {
    try {
      return JSON.parse(hit) as Cached;
    } catch {
      // entrée de cache corrompue : on la recalcule
    }
  }
  const incidents = await deps.traffic.fetchIncidents(bbox);
  const value: Cached = { incidents, fetchedAt: deps.now().toISOString() };
  await deps.cache.set(key, JSON.stringify(value), CACHE_TTL_SECONDS);
  return value;
}

export function registerTrafficRoutes(app: FastifyInstance, deps: Deps): void {
  app.get('/v1/traffic/incidents', async (request) => {
    const bbox = parseBbox((request.query as Record<string, unknown>).bbox);
    if (!deps.traffic.available) {
      return { available: false, provider: null, incidents: [], fetchedAt: deps.now().toISOString() };
    }
    try {
      const { incidents, fetchedAt } = await fetchIncidentsCached(deps, bbox);
      return { available: true, provider: deps.traffic.name, incidents, fetchedAt };
    } catch (err) {
      // Pas de données inventées : le service indique simplement qu'il est indisponible.
      app.log.warn({ err: (err as Error).message }, 'fournisseur de trafic en erreur');
      return { available: false, provider: deps.traffic.name, incidents: [], fetchedAt: deps.now().toISOString() };
    }
  });
}
