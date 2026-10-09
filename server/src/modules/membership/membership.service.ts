import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../infra/prisma.service';

// PRD §3.4 会员套餐 / 订单
@Injectable()
export class MembershipService {
  constructor(private readonly prisma: PrismaService) {}

  listPlans() {
    return this.prisma.membershipPlan.findMany({
      where: { isPublished: true },
      orderBy: { priceCents: 'asc' },
    });
  }

  // 后台
  createPlan(dto: any) {
    return this.prisma.membershipPlan.create({ data: dto });
  }
  updatePlan(id: string, dto: any) {
    return this.prisma.membershipPlan.update({ where: { id }, data: dto });
  }

  listOrders({ page = 1, pageSize = 20, userId, status }: {
    page: number; pageSize: number; userId?: string; status?: string;
  }) {
    return this.prisma.order.findMany({
      where: {
        ...(userId ? { userId } : {}),
        ...(status ? { status } : {}),
      },
      skip: (page - 1) * pageSize,
      take: pageSize,
      orderBy: { createdAt: 'desc' },
      include: { plan: true, user: { select: { id: true, nickname: true, email: true } } },
    });
  }

  // M4：客户端支付成功回调
  async markOrderPaid(orderId: string, externalTxId: string) {
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      include: { plan: true },
    });
    if (!order) throw new NotFoundException('Order not found');
    const expireAt = order.plan.durationDays > 0
      ? new Date(Date.now() + order.plan.durationDays * 24 * 3600 * 1000)
      : null; // 终身会员
    return this.prisma.order.update({
      where: { id: orderId },
      data: {
        status: 'paid',
        paidAt: new Date(),
        externalTxId,
        expireAt,
      },
    });
  }
}
