import { Body, Controller, Delete, Get, Param, Patch, Post, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Public } from '../../common/decorators/public.decorator';
import { CharactersService } from './characters.service';

@ApiTags('Characters')
@Controller('characters')
export class CharactersController {
  constructor(private readonly service: CharactersService) {}

  @Public()
  @Get('published')
  published() {
    return this.service.listPublished();
  }

  @Public()
  @Get('daily-pool')
  pool(@Query('date') date = new Date().toISOString().slice(0, 10)) {
    return this.service.poolForDate(new Date(date));
  }

  @Post('daily-pool')
  upsertPool(@Body() dto: { characterId: string; date: string }) {
    return this.service.upsertDailyPool(dto.characterId, new Date(dto.date));
  }

  @Get()
  list(@Query('page') page = '1', @Query('pageSize') pageSize = '50') {
    return this.service.list({ page: Number(page), pageSize: Number(pageSize) });
  }

  @Post()
  create(@Body() dto: any) {
    return this.service.create(dto);
  }

  @Patch(':id')
  update(@Param('id') id: string, @Body() dto: any) {
    return this.service.update(id, dto);
  }

  @Delete(':id')
  remove(@Param('id') id: string) {
    return this.service.remove(id);
  }
}
