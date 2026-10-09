import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../infra/prisma.service';

// PRD §3.5 数据运营看板
@Injectable()
export class StatsService {
  constructor(private readonly prisma: PrismaService) {}

  // 客户端拉取个人日聚合（M3 起接入）
  async dailyForUser(userId: string, date: string) {
    const start = new Date(date);
    const end = new Date(start.getTime() + 24 * 3600 * 1000);
    const records = await this.prisma.drinkRecord.findMany({
      where: { userId, drankAt: { gte: start, lt: end }, deleted: false },
    });
    const totalVolumeMl = records.reduce((s, r) => s + r.volumeMl, 0);
    const totalEffectiveMl = records.reduce((s, r) => s + r.effectiveMl, 0);
    return {
      date,
      totalVolumeMl,
      totalEffectiveMl,
      punchCount: records.length,
      beverageBreakdown: this.breakdownByCategory(records),
    };
  }

  async rangeForUser(userId: string, fromIso: string, toIso: string) {
    const records = await this.prisma.drinkRecord.findMany({
      where: {
        userId,
        drankAt: { gte: new Date(fromIso), lt: new Date(toIso) },
        deleted: false,
      },
      orderBy: { drankAt: 'asc' },
    });
    const byDay = new Map<string, any>();
    for (const r of records) {
      const key = r.drankAt.toISOString().slice(0, 10);
      const cur = byDay.get(key) ?? { date: key, totalVolumeMl: 0, totalEffectiveMl: 0, punchCount: 0 };
      cur.totalVolumeMl += r.volumeMl;
      cur.totalEffectiveMl += r.effectiveMl;
      cur.punchCount += 1;
      byDay.set(key, cur);
    }
    return [...byDay.values()];
  }

  // 后台看板：新增 / 活跃 / 留存（M5 实现）
  async dashboard(range: { from: string; to: string }) {
    const from = new Date(range.from);
    const to = new Date(range.to);
    const [newUsers, activeUsers, totalOrders] = await Promise.all([
      this.prisma.user.count({ where: { createdAt: { gte: from, lt: to } } }),
      this.prisma.user.count({ where: { lastLoginAt: { gte: from, lt: to } } }),
      this.prisma.order.count({ where: { createdAt: { gte: from, lt: to }, status: 'paid' } }),
    ]);
    return { range, newUsers, activeUsers, totalOrders };
  }

  private breakdownByCategory(records: any[]) {
    const m = new Map<string, number>();
    for (const r of records) {
      m.set(r.beverageCategory, (m.get(r.beverageCategory) ?? 0) + r.volumeMl);
    }
    return [...m.entries()].map(([category, ml]) => ({ category, ml }));
  }
}
