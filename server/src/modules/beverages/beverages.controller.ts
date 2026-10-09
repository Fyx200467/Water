import { Body, Controller, Delete, Get, Param, Patch, Post, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Public } from '../../common/decorators/public.decorator';
import { BeveragesService } from './beverages.service';

@ApiTags('Beverages')
@Controller('beverages')
export class BeveragesController {
  constructor(private readonly service: BeveragesService) {}

  @Public()
  @Get('published')
  published() {
    return this.service.listPublished();
  }

  // ---- 后台 ----
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
