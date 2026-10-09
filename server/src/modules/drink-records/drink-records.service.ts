import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../infra/prisma.service';

// PRD §4.2 同步队列：批量上传，client_id 去重
@Injectable()
export class DrinkRecordsService {
  constructor(private readonly prisma: PrismaService) {}

  async batchUpsert(userId: string, records: any[]) {
    const ops = records.map((r) =>
      this.prisma.drinkRecord.upsert({
        where: { clientId: r.clientId },
        create: {
          clientId: r.clientId,
          userId,
          beverageId: r.beverageId ?? null,
          beverageCategory: r.beverageCategory,
          beverageName: r.beverageName,
          volumeMl: r.volumeMl,
          effectiveMl: r.effectiveMl,
          drankAt: new Date(r.drankAt),
          deleted: r.deleted ?? false,
        },
        update: {
          beverageId: r.beverageId ?? null,
          beverageCategory: r.beverageCategory,
          beverageName: r.beverageName,
          volumeMl: r.volumeMl,
          effectiveMl: r.effectiveMl,
          drankAt: new Date(r.drankAt),
          deleted: r.deleted ?? false,
        },
      }),
    );
    return this.prisma.$transaction(ops);
  }

  listByDate(userId: string, date: string) {
    const start = new Date(date);
    const end = new Date(start.getTime() + 24 * 3600 * 1000);
    return this.prisma.drinkRecord.findMany({
      where: { userId, drankAt: { gte: start, lt: end }, deleted: false },
      orderBy: { drankAt: 'asc' },
    });
  }

  listByRange(userId: string, fromIso: string, toIso: string) {
    return this.prisma.drinkRecord.findMany({
      where: {
        userId,
        drankAt: { gte: new Date(fromIso), lt: new Date(toIso) },
        deleted: false,
      },
      orderBy: { drankAt: 'asc' },
    });
  }

  async softDelete(userId: string, clientId: string) {
    const rec = await this.prisma.drinkRecord.findUnique({ where: { clientId } });
    if (!rec || rec.userId !== userId) throw new NotFoundException();
    return this.prisma.drinkRecord.update({
      where: { clientId },
      data: { deleted: true },
    });
  }
}
