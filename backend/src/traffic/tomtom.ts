// Connecteur TomTom Traffic Incident Details v5.
// ATTENTION : écrit d'après la documentation publique, NON testé contre l'API réelle.
// Vérifier les conditions de licence et de redistribution de TomTom avant toute mise en production.
import type { Bbox } from '../services/geo.js';
import type { IncidentCategory, TrafficIncident, TrafficProvider } from './provider.js';

const BASE_URL = 'https://api.tomtom.com/traffic/services/5/incidentDetails';
const FIELDS =
  '{incidents{type,geometry{type,coordinates},properties{id,iconCategory,magnitudeOfDelay,events{description,code,iconCategory},startTime,endTime,delay}}}';

/** iconCategory TomTom → catégorie Strasse. */
export function mapTomTomCategory(icon: number | undefined): IncidentCategory {
  switch (icon) {
    case 1:
      return 'accident';
    case 6:
      return 'slowdown';
    case 7:
    case 8:
      return 'closure';
    case 9:
      return 'roadwork';
    case 2: // brouillard
    case 3: // conditions dangereuses
    case 4: // pluie
    case 5: // verglas
    case 10: // vent
    case 11: // inondation
    case 14: // véhicule en panne
      return 'danger';
    default:
      return 'other';
  }
}

function firstPoint(geometry: unknown): { lat: number; lon: number } | null {
  if (!geometry || typeof geometry !== 'object') return null;
  const g = geometry as { type?: string; coordinates?: unknown };
  let c: unknown = g.coordinates;
  if (g.type === 'LineString' && Array.isArray(c)) {
    // Point central de la ligne pour une position représentative.
    c = c[Math.floor(c.length / 2)];
  }
  if (Array.isArray(c) && typeof c[0] === 'number' && typeof c[1] === 'number') {
    return { lon: c[0], lat: c[1] };
  }
  return null;
}

/** Transforme la réponse JSON TomTom en incidents Strasse. Les entrées invalides sont ignorées. */
export function parseTomTomIncidents(json: unknown): TrafficIncident[] {
  const incidents = (json as { incidents?: unknown[] } | null)?.incidents;
  if (!Array.isArray(incidents)) return [];
  const out: TrafficIncident[] = [];
  for (const raw of incidents) {
    const item = raw as {
      geometry?: unknown;
      properties?: {
        id?: string;
        iconCategory?: number;
        events?: { description?: string }[];
        startTime?: string;
        endTime?: string;
        delay?: number;
      };
    };
    const props = item.properties;
    const pt = firstPoint(item.geometry);
    if (!props?.id || !pt) continue;
    const description = props.events?.find((e) => e.description)?.description;
    const incident: TrafficIncident = {
      id: props.id,
      category: mapTomTomCategory(props.iconCategory),
      lat: pt.lat,
      lon: pt.lon,
      source: 'tomtom',
    };
    if (description) incident.description = description;
    if (props.startTime) incident.startTime = props.startTime;
    if (props.endTime) incident.endTime = props.endTime;
    if (typeof props.delay === 'number' && props.delay > 0) incident.delayMinutes = Math.round(props.delay / 60);
    out.push(incident);
  }
  return out;
}

export class TomTomTrafficProvider implements TrafficProvider {
  readonly name = 'tomtom';
  readonly available = true;

  constructor(
    private readonly apiKey: string,
    private readonly fetchImpl: typeof fetch = fetch,
    private readonly timeoutMs = 8000,
  ) {}

  async fetchIncidents(b: Bbox, signal?: AbortSignal): Promise<TrafficIncident[]> {
    const params = new URLSearchParams({
      key: this.apiKey,
      bbox: `${b.minLon},${b.minLat},${b.maxLon},${b.maxLat}`,
      fields: FIELDS,
      language: 'fr-FR',
      timeValidityFilter: 'present',
    });
    const timeout = AbortSignal.timeout(this.timeoutMs);
    const res = await this.fetchImpl(`${BASE_URL}?${params}`, {
      signal: signal ? AbortSignal.any([signal, timeout]) : timeout,
    });
    if (!res.ok) throw new Error(`TomTom a répondu ${res.status}`);
    return parseTomTomIncidents(await res.json());
  }
}
