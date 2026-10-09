import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../infra/prisma.service';

// PRD §3.3 角色素材 + 每日可选池
@Injectable()
export class CharactersService {
  constructor(private readonly prisma: PrismaService) {}

  listPublished() {
    return this.prisma.characterAsset.findMany({
      where: { isPublished: true },
      orderBy: [{ sort: 'asc' }],
    });
  }

  // 每日可选池（按 activeDate）
  poolForDate(date: Date) {
    return this.prisma.dailyCharacterPool.findMany({
      where: { activeDate: date },
    });
  }

  async upsertDailyPool(characterId: string, date: Date) {
    return this.prisma.dailyCharacterPool.upsert({
      where: { characterId_activeDate: { characterId, activeDate: date } },
      create: { characterId, activeDate: date },
      update: {},
    });
  }

  create(dto: any) {
    return this.prisma.characterAsset.create({ data: dto });
  }
  update(id: string, dto: any) {
    return this.prisma.characterAsset.update({ where: { id }, data: dto });
  }
  remove(id: string) {
    return this.prisma.characterAsset.delete({ where: { id } });
  }
  list({ page = 1, pageSize = 50 }: { page: number; pageSize: number }) {
    return this.prisma.characterAsset.findMany({
      skip: (page - 1) * pageSize, take: pageSize,
      orderBy: [{ sort: 'asc' }],
    });
  }
}
