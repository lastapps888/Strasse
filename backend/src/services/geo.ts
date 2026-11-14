import { AppError } from '../errors.js';

export interface Bbox {
  minLon: number;
  minLat: number;
  maxLon: number;
  maxLat: number;
}

/** Côté maximal (en degrés) d'une zone demandée. */
export const MAX_BBOX_SPAN_DEG = 2;

const EARTH_RADIUS_M = 6_371_008.8;

/** Distance orthodromique en mètres (formule de haversine). */
export function haversineMeters(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(a)));
}

/** Analyse « minLon,minLat,maxLon,maxLat » ; lève une AppError 400 si invalide ou trop grande. */
export function parseBbox(raw: unknown, maxSpan = MAX_BBOX_SPAN_DEG): Bbox {
  if (typeof raw !== 'string') {
    throw new AppError(400, 'invalid_bbox', 'Le paramètre bbox est obligatoire (minLon,minLat,maxLon,maxLat).');
  }
  const parts = raw.split(',').map((p) => Number(p.trim()));
  if (parts.length !== 4 || parts.some((n) => !Number.isFinite(n))) {
    throw new AppError(400, 'invalid_bbox', 'Le paramètre bbox doit contenir quatre nombres.');
  }
  const [minLon, minLat, maxLon, maxLat] = parts as [number, number, number, number];
  if (minLon < -180 || maxLon > 180 || minLat < -90 || maxLat > 90 || minLon >= maxLon || minLat >= maxLat) {
    throw new AppError(400, 'invalid_bbox', 'Les coordonnées de la zone sont incohérentes.');
  }
  if (maxLon - minLon > maxSpan || maxLat - minLat > maxSpan) {
    throw new AppError(400, 'bbox_too_large', `La zone demandée est trop grande (maximum ${maxSpan}° de côté).`);
  }
  return { minLon, minLat, maxLon, maxLat };
}

/** Boîte englobant un cercle de rayon `meters` autour d'un point. */
export function bboxAround(lat: number, lon: number, meters: number): Bbox {
  const dLat = (meters / EARTH_RADIUS_M) * (180 / Math.PI);
  const cos = Math.max(0.01, Math.cos((lat * Math.PI) / 180));
  const dLon = dLat / cos;
  return {
    minLat: Math.max(-90, lat - dLat),
    maxLat: Math.min(90, lat + dLat),
    minLon: Math.max(-180, lon - dLon),
    maxLon: Math.min(180, lon + dLon),
  };
}

/** Arrondit une zone à 0,01° pour obtenir une clé de cache stable. */
export function bboxCacheKey(b: Bbox): string {
  const r = (n: number) => (Math.round(n * 100) / 100).toFixed(2);
  return `${r(b.minLon)},${r(b.minLat)},${r(b.maxLon)},${r(b.maxLat)}`;
}

export function isNullIsland(lat: number, lon: number): boolean {
  return lat === 0 && lon === 0;
}
