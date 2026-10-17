import "server-only";
import { Redis } from "@upstash/redis";
import { env } from "./env";

/**
 * Fast key-value store for rate limits, verification-attempt counters, circuit-breaker state and hot caches
 * (spec 3A). Upstash Redis in production; an in-memory store for local dev and tests.
 */
export interface KvStore {
  get<T>(key: string): Promise<T | null>;
  set(key: string, value: unknown, ttlSeconds?: number): Promise<void>;
  incr(key: string, ttlSeconds: number): Promise<number>;
  del(key: string): Promise<void>;
}

class MemoryKv implements KvStore {
  private m = new Map<string, { v: unknown; exp: number | null }>();
  private live(key: string) {
    const e = this.m.get(key);
    if (!e) return null;
    if (e.exp !== null && e.exp < Date.now()) {
      this.m.delete(key);
      return null;
    }
    return e;
  }
  async get<T>(key: string) {
    return (this.live(key)?.v as T) ?? null;
  }
  async set(key: string, value: unknown, ttl?: number) {
    this.m.set(key, { v: value, exp: ttl ? Date.now() + ttl * 1000 : null });
  }
  async incr(key: string, ttl: number) {
    const e = this.live(key);
    const n = (typeof e?.v === "number" ? e.v : 0) + 1;
    this.m.set(key, { v: n, exp: e?.exp ?? Date.now() + ttl * 1000 });
    return n;
  }
  async del(key: string) {
    this.m.delete(key);
  }
}

class UpstashKv implements KvStore {
  constructor(private r: Redis) {}
  async get<T>(key: string) {
    return (await this.r.get<T>(key)) ?? null;
  }
  async set(key: string, value: unknown, ttl?: number) {
    if (ttl) await this.r.set(key, value, { ex: ttl });
    else await this.r.set(key, value);
  }
  async incr(key: string, ttl: number) {
    const n = await this.r.incr(key);
    if (n === 1) await this.r.expire(key, ttl);
    return n;
  }
  async del(key: string) {
    await this.r.del(key);
  }
}

let store: KvStore | null = null;
const g = globalThis as unknown as { __ewMemKv?: MemoryKv };

export function kv(): KvStore {
  if (store) return store;
  const e = env();
  if (e.UPSTASH_REDIS_REST_URL && e.UPSTASH_REDIS_REST_TOKEN) {
    store = new UpstashKv(new Redis({ url: e.UPSTASH_REDIS_REST_URL, token: e.UPSTASH_REDIS_REST_TOKEN }));
  } else {
    g.__ewMemKv ??= new MemoryKv();
    store = g.__ewMemKv;
  }
  return store;
}

export { MemoryKv };
