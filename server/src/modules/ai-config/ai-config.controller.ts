import { Body, Controller, Get, Param, Patch, Post, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { AiConfigService } from './ai-config.service';

@ApiTags('AiConfig')
@Controller('ai-config')
export class AiConfigController {
  constructor(private readonly service: AiConfigService) {}

  // 后台：模型配置 CRUD
  @Get()
  list() {
    return this.service.listConfigs();
  }

  @Post()
  create(@Body() dto: any) {
    return this.service.createConfig(dto);
  }

  @Patch(':id')
  update(@Param('id') id: string, @Body() dto: any) {
    return this.service.updateConfig(id, dto);
  }

  // 后台：调用量 + 成本监控
  @Get('usage')
  usage(@Query('from') from: string, @Query('to') to: string) {
    return this.service.usageStats({ from, to });
  }
}
