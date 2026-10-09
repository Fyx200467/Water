import { Body, Controller, Get, Patch, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { UserService } from './user.service';

@ApiTags('User')
@Controller('user')
export class UserController {
  constructor(private readonly service: UserService) {}

  @Get('me')
  me(@CurrentUser() user: { userId: string }) {
    return this.service.getProfile(user.userId);
  }

  @Patch('me')
  update(@CurrentUser() user: { userId: string }, @Body() dto: any) {
    return this.service.updateProfile(user.userId, dto);
  }

  // PRD §3.1 后台用户列表
  @Get()
  list(@Query('page') page = '1', @Query('pageSize') pageSize = '20') {
    return this.service.list({
      page: Number(page), pageSize: Number(pageSize),
    });
  }
}
