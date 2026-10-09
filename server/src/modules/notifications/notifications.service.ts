import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../infra/prisma.service';

// PRD §2.4 推送 token + 定时提醒任务
@Injectable()
export class NotificationsService {
  constructor(private readonly prisma: PrismaService) {}

  async registerToken(userId: string, token: string, platform: string) {
    return this.prisma.pushToken.upsert({
      where: { userId_platform_token: { userId, platform, token } },
      create: { userId, token, platform, isActive: true },
      update: { isActive: true },
    });
  }

  async deactivate(userId: string, token: string) {
    const found = await this.prisma.pushToken.findFirst({
      where: { userId, token },
    });
    if (!found) return null;
    return this.prisma.pushToken.update({
      where: { id: found.id },
      data: { isActive: false },
    });
  }

  // 实际推送：APNs / FCM / 华为 / 小米 — M3 接入真实 SDK
  async sendToUser(userId: string, title: string, body: string) {
    const tokens = await this.prisma.pushToken.findMany({
      where: { userId, isActive: true },
    });
    // 占位：返回需要推送的设备列表
    return { queued: tokens.length, devices: tokens.map(t => ({ platform: t.platform, token: t.token })) };
  }
}
