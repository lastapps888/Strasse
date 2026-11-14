import { z } from 'zod';

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  HOST: z.string().default('0.0.0.0'),
  PORT: z.coerce.number().int().min(1).max(65535).default(8080),
  DATABASE_URL: z.string().optional(),
  REDIS_URL: z.string().optional(),
  JWT_SECRET: z.string().optional(),
  SERVER_SALT: z.string().optional(),
  SYNC_ENCRYPTION_KEY: z.string().optional(),
  ADMIN_TOKEN: z.string().optional(),
  TRAFFIC_PROVIDER: z.enum(['none', 'tomtom']).default('none'),
  TOMTOM_API_KEY: z.string().optional(),
  CORS_ORIGINS: z.string().default(''),
  RATE_LIMIT_MAX: z.coerce.number().int().min(1).default(300),
  MAINTENANCE_INTERVAL_SECONDS: z.coerce.number().int().min(5).default(60),
});

export type Config = z.infer<typeof schema> & {
  jwtSecret: string;
  serverSalt: string;
  syncKey: Buffer | null;
  corsOrigins: string[];
  warnings: string[];
};

const DEV_JWT = 'dev-only-jwt-secret-change-me-0123456789abcdef';
const DEV_SALT = 'dev-only-server-salt-change-me-0123456789abcdef';

/** Charge et valide la configuration. En production, les secrets sont obligatoires. */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const parsed = schema.safeParse(env);
  if (!parsed.success) {
    const details = parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('; ');
    throw new Error(`Configuration invalide : ${details}`);
  }
  const c = parsed.data;
  const warnings: string[] = [];
  const prod = c.NODE_ENV === 'production';

  if (prod) {
    if (!c.JWT_SECRET || c.JWT_SECRET.length < 32) {
      throw new Error('JWT_SECRET est obligatoire en production (32 caractères minimum).');
    }
    if (!c.SERVER_SALT || c.SERVER_SALT.length < 32) {
      throw new Error('SERVER_SALT est obligatoire en production (32 caractères minimum).');
    }
    if (!c.DATABASE_URL) {
      throw new Error('DATABASE_URL est obligatoire en production.');
    }
  } else {
    if (!c.JWT_SECRET) warnings.push('JWT_SECRET absent : secret de développement utilisé.');
    if (!c.SERVER_SALT) warnings.push('SERVER_SALT absent : sel de développement utilisé.');
  }

  let syncKey: Buffer | null = null;
  if (c.SYNC_ENCRYPTION_KEY) {
    syncKey = Buffer.from(c.SYNC_ENCRYPTION_KEY, 'base64');
    if (syncKey.length !== 32) {
      throw new Error('SYNC_ENCRYPTION_KEY doit contenir 32 octets encodés en base64.');
    }
  } else {
    warnings.push(
      'SYNC_ENCRYPTION_KEY absent : les données de synchronisation sont stockées en clair dans la base.',
    );
  }

  if (c.TRAFFIC_PROVIDER === 'tomtom' && !c.TOMTOM_API_KEY) {
    warnings.push('TRAFFIC_PROVIDER=tomtom sans TOMTOM_API_KEY : le trafic externe est désactivé.');
  }

  return {
    ...c,
    jwtSecret: c.JWT_SECRET ?? DEV_JWT,
    serverSalt: c.SERVER_SALT ?? DEV_SALT,
    syncKey,
    corsOrigins: c.CORS_ORIGINS.split(',').map((s) => s.trim()).filter(Boolean),
    warnings,
  };
}
