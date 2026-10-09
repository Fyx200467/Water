import { Module } from '@nestjs/common';
import { DrinkRecordsController } from './drink-records.controller';
import { DrinkRecordsService } from './drink-records.service';

@Module({
  controllers: [DrinkRecordsController],
  providers: [DrinkRecordsService],
})
export class DrinkRecordsModule {}
