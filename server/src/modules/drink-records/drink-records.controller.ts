import { Body, Controller, Delete, Get, Param, Post, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { DrinkRecordsService } from './drink-records.service';

@ApiTags('DrinkRecords')
@Controller('drink-records')
export class DrinkRecordsController {
  constructor(private readonly service: DrinkRecordsService) {}

  // PRD §4.2 客户端同步队列
  @Post('batch')
  batch(@CurrentUser() user: { userId: string }, @Body('records') records: any[]) {
    return this.service.batchUpsert(user.userId, records);
  }

  @Get()
  list(
    @CurrentUser() user: { userId: string },
    @Query('date') date: string,
    @Query('from') from: string,
    @Query('to') to: string,
  ) {
    if (date) return this.service.listByDate(user.userId, date);
    if (from && to) return this.service.listByRange(user.userId, from, to);
    return this.service.listByDate(user.userId, new Date().toISOString().slice(0, 10));
  }

  @Delete(':clientId')
  remove(@CurrentUser() user: { userId: string }, @Param('clientId') clientId: string) {
    return this.service.softDelete(user.userId, clientId);
  }
}
