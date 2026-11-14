export const REPORT_TYPES = [
  'accident',
  'roadwork',
  'slowdown',
  'closure',
  'obstacle',
  'danger',
  'other',
] as const;
export type ReportType = (typeof REPORT_TYPES)[number];

const MIN = 60_000;
const HOUR = 60 * MIN;

/** Durée de validité de base d'un signalement, en millisecondes. */
export const BASE_DURATION_MS: Record<ReportType, number> = {
  accident: 2 * HOUR,
  roadwork: 24 * HOUR,
  slowdown: 45 * MIN,
  closure: 6 * HOUR,
  obstacle: 1 * HOUR,
  danger: 1 * HOUR,
  other: 1 * HOUR,
};

/** Chaque confirmation prolonge de 25 % de la durée de base, plafonné à 3× la durée de base. */
export const EXTENSION_PER_CONFIRMATION = 0.25;
export const MAX_DURATION_FACTOR = 3;

/** Date d'expiration d'un signalement créé à `createdAt` avec `confirmations` confirmations. */
export function computeExpiry(type: ReportType, createdAt: Date, confirmations: number): Date {
  const base = BASE_DURATION_MS[type];
  const factor = Math.min(MAX_DURATION_FACTOR, 1 + EXTENSION_PER_CONFIRMATION * Math.max(0, confirmations));
  return new Date(createdAt.getTime() + base * factor);
}

/** Un signalement est masqué automatiquement lorsque rejets ≥ confirmations + 3. */
export function shouldAutoHide(confirmations: number, rejections: number): boolean {
  return rejections >= confirmations + 3;
}

export function isExpired(expiresAt: Date, now: Date): boolean {
  return expiresAt.getTime() <= now.getTime();
}
