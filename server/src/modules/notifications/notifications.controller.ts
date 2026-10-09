import { Body, Controller, Delete, Post } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { NotificationsService } from './notifications.service';

@ApiTags('Notifications')
@Controller('notifications')
export class NotificationsController {
  constructor(private readonly service: NotificationsService) {}

  @Post('token')
  register(
    @CurrentUser() user: { userId: string },
    @Body() dto: { token: string; platform: string },
  ) {
    return this.service.registerToken(user.userId, dto.token, dto.platform);
  }

  @Delete('token')
  deactivate(@CurrentUser() user: { userId: string }, @Body('token') token: string) {
    return this.service.deactivate(user.userId, token);
  }
}
