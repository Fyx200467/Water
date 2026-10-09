import { Controller, Get, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { StatsService } from './stats.service';

@ApiTags('Stats')
@Controller('stats')
export class StatsController {
  constructor(private readonly service: StatsService) {}

  @Get('daily')
  daily(@CurrentUser() user: { userId: string }, @Query('date') date = new Date().toISOString().slice(0, 10)) {
    return this.service.dailyForUser(user.userId, date);
  }

  @Get('range')
  range(
    @CurrentUser() user: { userId: string },
    @Query('from') from: string,
    @Query('to') to: string,
  ) {
    return this.service.rangeForUser(user.userId, from, to);
  }

  // PRD §3.5 后台看板
  @Get('dashboard')
  dashboard(@Query('from') from: string, @Query('to') to: string) {
    return this.service.dashboard({ from, to });
  }
}
