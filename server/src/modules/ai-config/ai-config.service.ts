import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../infra/prisma.service';
import { RedisService } from '../../infra/redis.service';

// PRD §3.6 AI 后台配置 + §4.2 限流 + V2.0 AI 接口
@Injectable()
export class AiConfigService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
  ) {}

  // V2.0 客户端调用 AI 时拿当前启用的 provider 配置（脱敏）
  async getActiveProvider() {
    const cached = await this.redis.get('ai:active_provider');
    if (cached) return JSON.parse(cached);
    const list = await this.prisma.aiConfig.findMany({ where: { isEnabled: true } });
    if (list.length === 0) return null;
    const active = list[0];
    const safe = {
      provider: active.provider,
      baseUrl: active.baseUrl,
      model: active.model,
      styleTemplate: active.styleTemplate,
    };
    await this.redis.set('ai:active_provider', JSON.stringify(safe), 60);
    return safe;
  }

  // PRD §3.6 限流：60 次 / 分钟 / 用户
  async checkRateLimit(userId: string): Promise<boolean> {
    const key = `ai:rl:${userId}:${Math.floor(Date.now() / 60000)}`;
    return this.redis.incrAndCheck(key, 60, 70);
  }

  async logUsage(dto: {
    userId: string; feature: string; promptTokens: number;
    completionTokens: number; latencyMs: number; costCents: number;
    isSuccess: boolean; error?: string;
  }) {
    return this.prisma.aiUsageLog.create({ data: dto });
  }

  // 后台管理
  listConfigs() {
    return this.prisma.aiConfig.findMany({ orderBy: { createdAt: 'desc' } });
  }
  createConfig(dto: any) {
    return this.prisma.aiConfig.create({ data: dto });
  }
  updateConfig(id: string, dto: any) {
    return this.prisma.aiConfig.update({ where: { id }, data: dto });
  }

  async usageStats({ from, to }: { from: string; to: string }) {
    const [logs, totalCost, totalCalls] = await Promise.all([
      this.prisma.aiUsageLog.findMany({
        where: { createdAt: { gte: new Date(from), lt: new Date(to) } },
        orderBy: { createdAt: 'desc' },
        take: 100,
      }),
      this.prisma.aiUsageLog.aggregate({
        where: { createdAt: { gte: new Date(from), lt: new Date(to) } },
        _sum: { costCents: true },
      }),
      this.prisma.aiUsageLog.count({
        where: { createdAt: { gte: new Date(from), lt: new Date(to) } },
      }),
    ]);
    return { logs, totalCostCents: totalCost._sum.costCents ?? 0, totalCalls };
  }
}
