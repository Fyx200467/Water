import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../infra/prisma.service';

// PRD §3.2 饮品库后台 / 下发
@Injectable()
export class BeveragesService {
  constructor(private readonly prisma: PrismaService) {}

  // 客户端拉取已发布饮品
  listPublished() {
    return this.prisma.beverage.findMany({
      where: { isPublished: true },
      orderBy: [{ sort: 'asc' }, { createdAt: 'asc' }],
    });
  }

  // 后台管理（增删改）
  create(dto: any) {
    return this.prisma.beverage.create({ data: dto });
  }
  update(id: string, dto: any) {
    return this.prisma.beverage.update({ where: { id }, data: dto });
  }
  remove(id: string) {
    return this.prisma.beverage.delete({ where: { id } });
  }
  list({ page = 1, pageSize = 50 }: { page: number; pageSize: number }) {
    return this.prisma.beverage.findMany({
      skip: (page - 1) * pageSize,
      take: pageSize,
      orderBy: [{ sort: 'asc' }, { createdAt: 'asc' }],
    });
  }
}
