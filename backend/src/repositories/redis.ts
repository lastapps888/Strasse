import { Redis } from 'ioredis';
import type { AbuseCounter, KeyValueCache } from './interfaces.js';

export function createRedis(url: string): Redis {
  return new Redis(url, { maxRetriesPerRequest: 2, enableOfflineQueue: false, lazyConnect: false });
}

/** Compteur à fenêtre fixe : INCR puis EXPIRE à la première touche. */
export class RedisAbuseCounter implements AbuseCounter {
  constructor(private readonly redis: Redis) {}

  async hit(key: string, windowSeconds: number): Promise<number> {
    const k = `abuse:${key}`;
    const count = await this.redis.incr(k);
    if (count === 1) await this.redis.expire(k, windowSeconds);
    return count;
  }
}

export class RedisCache implements KeyValueCache {
  constructor(private readonly redis: Redis) {}

  async get(key: string): Promise<string | null> {
    return this.redis.get(`cache:${key}`);
  }
  async set(key: string, value: string, ttlSeconds: number): Promise<void> {
    await this.redis.set(`cache:${key}`, value, 'EX', ttlSeconds);
  }
}
