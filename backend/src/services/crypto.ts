import { createCipheriv, createDecipheriv, createHash, createHmac, randomBytes } from 'node:crypto';

const PREFIX = 'enc:v1:';

/** Chiffre `plain` en AES-256-GCM. Sortie : « enc:v1: » + base64(iv ‖ tag ‖ chiffré). */
export function encryptString(plain: string, key: Buffer): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const enc = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
  return PREFIX + Buffer.concat([iv, cipher.getAuthTag(), enc]).toString('base64');
}

/** Déchiffre une valeur produite par `encryptString`. Une valeur non chiffrée est renvoyée telle quelle. */
export function decryptString(stored: string, key: Buffer | null): string {
  if (!stored.startsWith(PREFIX)) return stored;
  if (!key) throw new Error('Donnée chiffrée mais SYNC_ENCRYPTION_KEY est absent.');
  const raw = Buffer.from(stored.slice(PREFIX.length), 'base64');
  const iv = raw.subarray(0, 12);
  const tag = raw.subarray(12, 28);
  const data = raw.subarray(28);
  const decipher = createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(data), decipher.final()]).toString('utf8');
}

export function sealForStorage(plain: string, key: Buffer | null): string {
  return key ? encryptString(plain, key) : plain;
}

export function sha256Hex(value: string): string {
  return createHash('sha256').update(value).digest('hex');
}

/** Pseudonyme irréversible d'un identifiant d'installation (jamais publié ni lié publiquement). */
export function hashInstallId(installId: string, salt: string): string {
  return createHmac('sha256', salt).update(installId).digest('hex');
}
