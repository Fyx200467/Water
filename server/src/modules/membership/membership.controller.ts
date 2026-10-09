import { Body, Controller, Get, Param, Patch, Post, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Public } from '../../common/decorators/public.decorator';
import { MembershipService } from './membership.service';

@ApiTags('Membership')
@Controller('membership')
export class MembershipController {
  constructor(private readonly service: MembershipService) {}

  @Public()
  @Get('plans')
  plans() {
    return this.service.listPlans();
  }

  // 后台
  @Get('orders')
  orders(
    @Query('page') page = '1',
    @Query('pageSize') pageSize = '20',
    @Query('userId') userId?: string,
    @Query('status') status?: string,
  ) {
    return this.service.listOrders({
      page: Number(page), pageSize: Number(pageSize),
      userId, status,
    });
  }

  @Post('plans')
  createPlan(@Body() dto: any) {
    return this.service.createPlan(dto);
  }

  @Patch('plans/:id')
  updatePlan(@Param('id') id: string, @Body() dto: any) {
    return this.service.updatePlan(id, dto);
  }

  // M4：iOS IAP / Google Play 回调
  @Patch('orders/:id/paid')
  paid(@Param('id') id: string, @Body('externalTxId') externalTxId: string) {
    return this.service.markOrderPaid(id, externalTxId);
  }
}
