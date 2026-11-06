import type { Bbox } from '../services/geo.js';
import type { TrafficIncident, TrafficProvider } from './provider.js';

/** Aucun fournisseur configuré : le service le dit clairement et ne renvoie aucune donnée. */
export class NoTrafficProvider implements TrafficProvider {
  readonly name = 'none';
  readonly available = false;

  async fetchIncidents(_bbox: Bbox): Promise<TrafficIncident[]> {
    return [];
  }
}
