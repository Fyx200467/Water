import { Body, Controller, Post } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Public } from '../../common/decorators/public.decorator';
import { AuthService } from './auth.service';

class RegisterDto { email: string; password: string; nickname?: string; }
class LoginDto { email: string; password: string; }
class OpenIdDto { openId: string; platform: string; nickname?: string; }

@ApiTags('Auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Public()
  @Post('register')
  register(@Body() dto: RegisterDto) {
    return this.auth.registerByEmail(dto.email, dto.password, dto.nickname);
  }

  @Public()
  @Post('login')
  login(@Body() dto: LoginDto) {
    return this.auth.loginByEmail(dto.email, dto.password);
  }

  @Public()
  @Post('open-id')
  openId(@Body() dto: OpenIdDto) {
    return this.auth.loginByOpenId(dto.openId, dto.platform, dto.nickname);
  }
}
