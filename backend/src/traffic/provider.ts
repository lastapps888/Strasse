import type { Bbox } from '../services/geo.js';

export type IncidentCategory = 'accident' | 'roadwork' | 'slowdown' | 'closure' | 'danger' | 'other';

export interface TrafficIncident {
  id: string;
  category: IncidentCategory;
  description?: string;
  lat: number;
  lon: number;
  startTime?: string;
  endTime?: string;
  delayMinutes?: number;
  source: string;
}

/** Connecteur de données de circulation. Un fournisseur ne renvoie jamais de données inventées. */
export interface TrafficProvider {
  readonly name: string;
  /** Faux si aucun fournisseur réel n'est configuré. */
  readonly available: boolean;
  fetchIncidents(bbox: Bbox, signal?: AbortSignal): Promise<TrafficIncident[]>;
}
