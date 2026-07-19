import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import type { Request } from 'express';
import {
  extractAdminTokenFromHeaders,
  getAdminApiKey,
  verifyAdminApiKey,
} from './admin-auth.js';

/**
 * Protects admin mutations and sensitive reads. When ADMIN_API_KEY is unset
 * (typical local dev), all requests pass — production must set the key.
 */
@Injectable()
export class AdminAuthGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    if (!getAdminApiKey()) return true;

    const request = context.switchToHttp().getRequest<Request>();
    const token = extractAdminTokenFromHeaders(
      request.headers as Record<string, string | string[] | undefined>,
    );

    if (!verifyAdminApiKey(token)) {
      throw new UnauthorizedException('ADMIN_AUTH_REQUIRED');
    }
    return true;
  }
}
