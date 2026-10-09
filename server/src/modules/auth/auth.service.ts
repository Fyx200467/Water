import { Injectable, UnauthorizedException, ConflictException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import * as bcrypt from 'bcrypt';
import { PrismaService } from '../../infra/prisma.service';

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}

  // PRD §3.1 用户注册 / 登录
  async registerByEmail(email: string, password: string, nickname?: string) {
    const exist = await this.prisma.user.findUnique({ where: { email } });
    if (exist) throw new ConflictException('Email already registered');
    const passwordHash = await bcrypt.hash(password, 10);
    const user = await this.prisma.user.create({
      data: { email, passwordHash, nickname },
    });
    return this.issueTokens(user.id, { email: user.email });
  }

  async loginByEmail(email: string, password: string) {
    const user = await this.prisma.user.findUnique({ where: { email } });
    if (!user || !user.passwordHash) throw new UnauthorizedException('Invalid credentials');
    const ok = await bcrypt.compare(password, user.passwordHash);
    if (!ok) throw new UnauthorizedException('Invalid credentials');
    await this.prisma.user.update({
      where: { id: user.id },
      data: { lastLoginAt: new Date() },
    });
    return this.issueTokens(user.id, { email: user.email });
  }

  // 微信 / Apple ID 第三方登录（M4 接入真实 OAuth）
  async loginByOpenId(openId: string, platform: string, nickname?: string) {
    let user = await this.prisma.user.findUnique({ where: { openId } });
    if (!user) {
      user = await this.prisma.user.create({
        data: { openId, nickname: nickname ?? `user_${openId.slice(0, 6)}` },
      });
    }
    return this.issueTokens(user.id, { openId: user.openId });
  }

  private async issueTokens(userId: string, extra: Record<string, unknown>) {
    const payload = { sub: userId, ...extra };
    const accessToken = await this.jwt.signAsync(payload);
    return { accessToken, userId };
  }
}
