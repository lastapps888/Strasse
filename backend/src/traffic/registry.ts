import type { Config } from '../config.js';
import { NoTrafficProvider } from './none.js';
import type { TrafficProvider } from './provider.js';
import { TomTomTrafficProvider } from './tomtom.js';

/** Fournisseur choisi par TRAFFIC_PROVIDER ; retombe sur « none » si la clé manque. */
export function createTrafficProvider(config: Config): TrafficProvider {
  if (config.TRAFFIC_PROVIDER === 'tomtom' && config.TOMTOM_API_KEY) {
    return new TomTomTrafficProvider(config.TOMTOM_API_KEY);
  }
  return new NoTrafficProvider();
}
