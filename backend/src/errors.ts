/** Erreur applicative : statut HTTP + code stable + message en français. */
export class AppError extends Error {
  readonly status: number;
  readonly statusCode: number;
  readonly code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.name = 'AppError';
    this.status = status;
    this.statusCode = status;
    this.code = code;
  }
}

export const Errors = {
  validation: (message = 'Les données envoyées sont invalides.') =>
    new AppError(400, 'validation_error', message),
  unauthorized: (message = 'Authentification requise.') => new AppError(401, 'unauthorized', message),
  forbidden: (message = 'Accès refusé.') => new AppError(403, 'forbidden', message),
  notFound: (message = 'Ressource introuvable.') => new AppError(404, 'not_found', message),
  conflict: (code: string, message: string) => new AppError(409, code, message),
  tooMany: (message = 'Trop de requêtes. Réessayez dans quelques instants.') =>
    new AppError(429, 'rate_limited', message),
};
