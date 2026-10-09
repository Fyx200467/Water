import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { PrismaModule } from './infra/prisma.module';
import { RedisModule } from './infra/redis.module';
import { AuthModule } from './modules/auth/auth.module';
import { UserModule } from './modules/user/user.module';
import { DrinkRecordsModule } from './modules/drink-records/drink-records.module';
import { BeveragesModule } from './modules/beverages/beverages.module';
import { CharactersModule } from './modules/characters/characters.module';
import { MembershipModule } from './modules/membership/membership.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { StatsModule } from './modules/stats/stats.module';
import { AiConfigModule } from './modules/ai-config/ai-config.module';
import { JwtAuthGuard } from './common/guards/jwt-auth.guard';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: ['.env.local', '.env'],
    }),
    PrismaModule,
    RedisModule,
    // PRD §3 各业务模块
    AuthModule,
    UserModule,
    DrinkRecordsModule,
    BeveragesModule,
    CharactersModule,
    MembershipModule,
    NotificationsModule,
    StatsModule,
    AiConfigModule,
  ],
  providers: [
    // 全局鉴权守卫（公开路由用 @Public 装饰器排除）
    { provide: APP_GUARD, useClass: JwtAuthGuard },
  ],
})
export class AppModule {}
