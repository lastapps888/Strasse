import { randomUUID } from 'node:crypto';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { Config } from '../config.js';
import type { Deps } from '../deps.js';
import { AppError, Errors } from '../errors.js';
import { burnPasswordCheck, hashPassword, verifyPassword } from '../services/password.js';
import {
  REFRESH_TTL_MS,
  hashRefreshToken,
  newRefreshToken,
  signAccessToken,
  verifyAccessToken,
} from '../services/tokens.js';

declare module 'fastify' {
  interface FastifyRequest {
    userId?: string;
  }
}

const credentials = z.object({
  email: z.string().trim().toLowerCase().email().max(254),
  password: z.string().min(10, 'Le mot de passe doit contenir au moins 10 caractères.').max(200),
});
const refreshBody = z.object({ refreshToken: z.string().min(20).max(200) });

export function requireAuth(config: Config) {
  return async (request: FastifyRequest): Promise<void> => {
    const header = request.headers.authorization;
    const token = header?.startsWith('Bearer ') ? header.slice(7) : null;
    const userId = token ? await verifyAccessToken(token, config.jwtSecret) : null;
    if (!userId) throw Errors.unauthorized('Session expirée ou invalide. Veuillez vous reconnecter.');
    request.userId = userId;
  };
}

export function registerAuthRoutes(app: FastifyInstance, config: Config, deps: Deps): void {
  const auth = requireAuth(config);

  async function issueTokens(userId: string, familyId: string) {
    const refresh = newRefreshToken();
    await deps.refreshTokens.insert({
      tokenHash: refresh.hash,
      userId,
      familyId,
      expiresAt: new Date(deps.now().getTime() + REFRESH_TTL_MS),
      revoked: false,
    });
    const accessToken = await signAccessToken(userId, config.jwtSecret, deps.now());
    return { accessToken, refreshToken: refresh.token };
  }

  app.post('/v1/auth/register', async (request, reply) => {
    const body = credentials.safeParse(request.body);
    if (!body.success) throw Errors.validation(body.error.issues[0]?.message);
    const { email, password } = body.data;
    if (await deps.users.findByEmail(email)) {
      throw Errors.conflict('email_taken', 'Un compte existe déjà avec cet e-mail.');
    }
    const user = { id: randomUUID(), email, passwordHash: await hashPassword(password), createdAt: deps.now() };
    await deps.users.create(user);
    const tokens = await issueTokens(user.id, randomUUID());
    return reply.code(201).send({ ...tokens, user: { id: user.id, email } });
  });

  app.post('/v1/auth/login', async (request) => {
    const body = credentials.safeParse(request.body);
    if (!body.success) throw Errors.validation(body.error.issues[0]?.message);
    const { email, password } = body.data;
    const user = await deps.users.findByEmail(email);
    if (!user) {
      await burnPasswordCheck(password);
      throw new AppError(401, 'invalid_credentials', 'E-mail ou mot de passe incorrect.');
    }
    if (!(await verifyPassword(password, user.passwordHash))) {
      throw new AppError(401, 'invalid_credentials', 'E-mail ou mot de passe incorrect.');
    }
    const tokens = await issueTokens(user.id, randomUUID());
    return { ...tokens, user: { id: user.id, email: user.email } };
  });

  app.post('/v1/auth/refresh', async (request) => {
    const body = refreshBody.safeParse(request.body);
    if (!body.success) throw Errors.validation('Jeton de rafraîchissement manquant.');
    const hash = hashRefreshToken(body.data.refreshToken);
    const record = await deps.refreshTokens.findByHash(hash);
    if (!record) throw new AppError(401, 'invalid_refresh_token', 'Session invalide. Veuillez vous reconnecter.');
    if (record.revoked) {
      // Réutilisation d'un jeton déjà consommé : on révoque toute la famille.
      await deps.refreshTokens.revokeFamily(record.familyId);
      throw new AppError(401, 'token_reuse_detected', 'Session révoquée par sécurité. Veuillez vous reconnecter.');
    }
    if (record.expiresAt.getTime() <= deps.now().getTime()) {
      throw new AppError(401, 'invalid_refresh_token', 'Session expirée. Veuillez vous reconnecter.');
    }
    await deps.refreshTokens.revoke(hash);
    return issueTokens(record.userId, record.familyId);
  });

  app.post('/v1/auth/logout', { preHandler: auth }, async (request, reply) => {
    const body = refreshBody.safeParse(request.body);
    if (!body.success) throw Errors.validation('Jeton de rafraîchissement manquant.');
    const record = await deps.refreshTokens.findByHash(hashRefreshToken(body.data.refreshToken));
    if (record && record.userId === request.userId) await deps.refreshTokens.revokeFamily(record.familyId);
    return reply.code(204).send();
  });

  app.delete('/v1/account', { preHandler: auth }, async (request, reply) => {
    const userId = request.userId as string;
    await deps.sync.deleteAllForUser(userId);
    await deps.refreshTokens.deleteByUser(userId);
    await deps.users.delete(userId);
    return reply.code(204).send();
  });
}
