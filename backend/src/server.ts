import { buildApp } from './app.js';
import { loadConfig } from './config.js';
import { createPool } from './db/pool.js';
import type { Deps } from './deps.js';
import {
  MemoryAbuseCounter,
  MemoryCache,
  MemoryRefreshTokenRepository,
  MemoryReportRepository,
  MemorySyncRepository,
  MemoryUserRepository,
} from './repositories/memory/index.js';
import {
  PgRefreshTokenRepository,
  PgReportRepository,
  PgSyncRepository,
  PgUserRepository,
} from './repositories/postgres/index.js';
import { RedisAbuseCounter, RedisCache, createRedis } from './repositories/redis.js';
import { createTrafficProvider } from './traffic/registry.js';

async function main(): Promise<void> {
  const config = loadConfig();
  const now = () => new Date();

  const deps: Deps = {
    users: new MemoryUserRepository(),
    refreshTokens: new MemoryRefreshTokenRepository(),
    sync: new MemorySyncRepository(),
    reports: new MemoryReportRepository(),
    counters: new MemoryAbuseCounter(now),
    cache: new MemoryCache(now),
    traffic: createTrafficProvider(config),
    now,
  };
  const notes: string[] = [...config.warnings];

  if (config.DATABASE_URL) {
    const pool = createPool(config.DATABASE_URL);
    deps.users = new PgUserRepository(pool);
    deps.refreshTokens = new PgRefreshTokenRepository(pool);
    deps.sync = new PgSyncRepository(pool);
    deps.reports = new PgReportRepository(pool);
  } else {
    notes.push('DATABASE_URL absent : stockage en mémoire, les données seront perdues à l\'arrêt (développement uniquement).');
  }

  if (config.REDIS_URL) {
    const redis = createRedis(config.REDIS_URL);
    redis.on('error', (err: Error) => console.warn(`Redis : ${err.message}`));
    deps.counters = new RedisAbuseCounter(redis);
    deps.cache = new RedisCache(redis);
  } else {
    notes.push('REDIS_URL absent : compteurs et cache en mémoire.');
  }

  const app = await buildApp(config, deps);
  for (const n of notes) app.log.warn(n);
  await app.listen({ host: config.HOST, port: config.PORT });
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
