import { Injectable, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import IORedis from 'ioredis';

@Injectable()
export class RedisService implements OnModuleInit, OnModuleDestroy {
  private client: IORedis;

  constructor(private readonly config: ConfigService) {}

  onModuleInit() {
    this.client = new IORedis(this.config.get<string>('REDIS_URL', 'redis://localhost:6379'), {
      maxRetriesPerRequest: 3,
      enableReadyCheck: true,
    });
    this.client.on('error', (err) => {
      // eslint-disable-next-line no-console
      console.error('Redis error:', err.message);
    });
  }

  async onModuleDestroy() {
    await this.client?.quit();
  }

  async get(key: string): Promise<string | null> {
    return this.client.get(key);
  }

  async set(key: string, value: string, ttlSeconds?: number): Promise<void> {
    if (ttlSeconds) {
      await this.client.set(key, value, 'EX', ttlSeconds);
    } else {
      await this.client.set(key, value);
    }
  }

  async del(key: string): Promise<void> {
    await this.client.del(key);
  }

  // PRD §4.2 限流 / 会话
  async incrAndCheck(key: string, limit: number, windowSec: number): Promise<boolean> {
    const cnt = await this.client.incr(key);
    if (cnt === 1) {
      await this.client.expire(key, windowSec);
    }
    return cnt <= limit;
  }
}
