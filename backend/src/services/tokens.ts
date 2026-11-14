import { randomBytes } from 'node:crypto';
import { SignJWT, jwtVerify } from 'jose';
import { sha256Hex } from './crypto.js';

export const ACCESS_TTL_SECONDS = 15 * 60;
export const REFRESH_TTL_MS = 30 * 24 * 60 * 60 * 1000;

const ISSUER = 'strasse';
const AUDIENCE = 'strasse-api';

export async function signAccessToken(userId: string, secret: string, now = new Date()): Promise<string> {
  return new SignJWT({})
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(userId)
    .setIssuer(ISSUER)
    .setAudience(AUDIENCE)
    .setIssuedAt(Math.floor(now.getTime() / 1000))
    .setExpirationTime(Math.floor(now.getTime() / 1000) + ACCESS_TTL_SECONDS)
    .sign(new TextEncoder().encode(secret));
}

/** Retourne l'identifiant utilisateur, ou null si le jeton est invalide ou expiré. */
export async function verifyAccessToken(token: string, secret: string): Promise<string | null> {
  try {
    const { payload } = await jwtVerify(token, new TextEncoder().encode(secret), {
      issuer: ISSUER,
      audience: AUDIENCE,
      algorithms: ['HS256'],
    });
    return typeof payload.sub === 'string' ? payload.sub : null;
  } catch {
    return null;
  }
}

/** Jeton de rafraîchissement opaque : seul son hachage est stocké. */
export function newRefreshToken(): { token: string; hash: string } {
  const token = randomBytes(32).toString('base64url');
  return { token, hash: sha256Hex(token) };
}

export function hashRefreshToken(token: string): string {
  return sha256Hex(token);
}
