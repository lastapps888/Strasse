import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { buildApp } from '../src/app.js';
import { loadConfig, type Config } from '../src/config.js';
import type { Deps } from '../src/deps.js';
import {
  MemoryAbuseCounter,
  MemoryCache,
  MemoryRefreshTokenRepository,
  MemoryReportRepository,
  MemorySyncRepository,
  MemoryUserRepository,
} from '../src/repositories/memory/index.js';
import { NoTrafficProvider } from '../src/traffic/none.js';
import type { TrafficProvider } from '../src/traffic/provider.js';

export class Clock {
  constructor(public current = new Date('2026-11-04T12:00:00.000Z')) {}
  now = () => new Date(this.current);
  advance(ms: number) {
    this.current = new Date(this.current.getTime() + ms);
  }
}

export interface TestContext {
  app: FastifyInstance;
  deps: Deps;
  config: Config;
  clock: Clock;
  users: MemoryUserRepository;
  tokens: MemoryRefreshTokenRepository;
  sync: MemorySyncRepository;
  reports: MemoryReportRepository;
}

export async function makeApp(
  env: Record<string, string> = {},
  traffic: TrafficProvider = new NoTrafficProvider(),
): Promise<TestContext> {
  const config = loadConfig({
    NODE_ENV: 'test',
    JWT_SECRET: 'test-jwt-secret-0123456789abcdef0123456789',
    SERVER_SALT: 'test-server-salt-0123456789abcdef0123456789',
    ...env,
  });
  const clock = new Clock();
  const users = new MemoryUserRepository();
  const tokens = new MemoryRefreshTokenRepository();
  const sync = new MemorySyncRepository();
  const reports = new MemoryReportRepository();
  const deps: Deps = {
    users,
    refreshTokens: tokens,
    sync,
    reports,
    counters: new MemoryAbuseCounter(clock.now),
    cache: new MemoryCache(clock.now),
    traffic,
    now: clock.now,
  };
  const app = await buildApp(config, deps);
  return { app, deps, config, clock, users, tokens, sync, reports };
}

export const newInstallId = () => randomUUID();

export async function register(app: FastifyInstance, email = 'ada@example.org', password = 'un-mot-de-passe-solide') {
  const res = await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password } });
  return { res, body: res.json() as { accessToken: string; refreshToken: string; user: { id: string; email: string } } };
}

export const bearer = (token: string) => ({ authorization: `Bearer ${token}` });
