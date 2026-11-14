export interface ReliabilityInput {
  createdAt: Date;
  expiresAt: Date;
  now: Date;
  confirmations: number;
  rejections: number;
  /** Un incident externe de même catégorie existe à proximité. */
  externalCorroboration?: boolean;
}

export const MIN_RELIABILITY = 0.02;
export const MAX_RELIABILITY = 0.98;

/**
 * Fiabilité estimée d'un signalement, entre 0,02 et 0,98 (jamais 0 ni 1 : une information
 * communautaire n'est jamais une certitude).
 *
 * Modèle logistique :
 *   logit = -0,2
 *           + 0,6 × confirmations
 *           - 0,8 × rejets
 *           + 1,0 × (fraîcheur - 0,5)        fraîcheur = part de validité restante, entre 0 et 1
 *           + 1,0 si un incident externe de même catégorie est proche
 *   fiabilité = 1 / (1 + e^-logit), bornée.
 */
export function computeReliability(input: ReliabilityInput): number {
  const total = Math.max(1, input.expiresAt.getTime() - input.createdAt.getTime());
  const remaining = input.expiresAt.getTime() - input.now.getTime();
  const freshness = Math.min(1, Math.max(0, remaining / total));
  const logit =
    -0.2 +
    0.6 * Math.max(0, input.confirmations) -
    0.8 * Math.max(0, input.rejections) +
    1.0 * (freshness - 0.5) +
    (input.externalCorroboration ? 1.0 : 0);
  const p = 1 / (1 + Math.exp(-logit));
  return Math.min(MAX_RELIABILITY, Math.max(MIN_RELIABILITY, p));
}
