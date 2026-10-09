import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../infra/prisma.service';
import { CurrentUserPayload } from '../../common/decorators/current-user.decorator';

@Injectable()
export class UserService {
  constructor(private readonly prisma: PrismaService) {}

  // PRD §3.1 用户基础信息查询 / 修改
  getProfile(userId: string) {
    return this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true, nickname: true, email: true, phone: true,
        gender: true, weightKg: true, heightCm: true,
        age: true, activityLevel: true, dailyGoalMl: true,
        avatarUrl: true, createdAt: true, updatedAt: true,
      },
    });
  }

  async updateProfile(userId: string, dto: Partial<{
    nickname: string; gender: string; weightKg: number; heightCm: number;
    age: number; activityLevel: string; dailyGoalMl: number; avatarUrl: string;
  }>) {
    return this.prisma.user.update({ where: { id: userId }, data: dto });
  }

  list({ page = 1, pageSize = 20 }: { page: number; pageSize: number }) {
    return this.prisma.user.findMany({
      skip: (page - 1) * pageSize,
      take: pageSize,
      orderBy: { createdAt: 'desc' },
    });
  }

  getById(id: string) {
    return this.prisma.user.findUnique({ where: { id } });
  }
}

export type { CurrentUserPayload };
