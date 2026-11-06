import { haversineMeters } from './geo.js';
import type { ReportType } from './expiry.js';

export const DUPLICATE_RADIUS_METERS = 150;

interface Candidate {
  id: string;
  type: ReportType;
  lat: number;
  lon: number;
  expiresAt: Date;
  status: string;
}

/** Signalement actif de même type à moins de 150 m, le plus proche en premier. */
export function findDuplicate<T extends Candidate>(
  candidates: readonly T[],
  type: ReportType,
  lat: number,
  lon: number,
  now: Date,
  radius = DUPLICATE_RADIUS_METERS,
): T | undefined {
  let best: T | undefined;
  let bestDist = Infinity;
  for (const c of candidates) {
    if (c.type !== type || c.status !== 'active' || c.expiresAt.getTime() <= now.getTime()) continue;
    const d = haversineMeters(lat, lon, c.lat, c.lon);
    if (d <= radius && d < bestDist) {
      best = c;
      bestDist = d;
    }
  }
  return best;
}
