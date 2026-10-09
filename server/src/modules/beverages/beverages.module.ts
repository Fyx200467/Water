import { Module } from '@nestjs/common';
import { BeveragesController } from './beverages.controller';
import { BeveragesService } from './beverages.service';

@Module({
  controllers: [BeveragesController],
  providers: [BeveragesService],
})
export class BeveragesModule {}
