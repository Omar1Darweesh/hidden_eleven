import { UnauthorizedException } from '@nestjs/common';
import { AdminAuthGuard } from './admin-auth.guard';

describe('AdminAuthGuard', () => {
  const guard = new AdminAuthGuard();
  const originalKey = process.env.ADMIN_API_KEY;

  afterEach(() => {
    if (originalKey === undefined) {
      delete process.env.ADMIN_API_KEY;
    } else {
      process.env.ADMIN_API_KEY = originalKey;
    }
  });

  function makeContext(headers: Record<string, string>) {
    return {
      switchToHttp: () => ({
        getRequest: () => ({ headers }),
      }),
    } as Parameters<AdminAuthGuard['canActivate']>[0];
  }

  it('allows all requests when ADMIN_API_KEY is unset', () => {
    delete process.env.ADMIN_API_KEY;
    expect(guard.canActivate(makeContext({}))).toBe(true);
  });

  it('accepts a valid Bearer token', () => {
    process.env.ADMIN_API_KEY = 'test-secret-key';
    expect(
      guard.canActivate(
        makeContext({ authorization: 'Bearer test-secret-key' }),
      ),
    ).toBe(true);
  });

  it('accepts a valid X-Admin-Key header', () => {
    process.env.ADMIN_API_KEY = 'test-secret-key';
    expect(
      guard.canActivate(makeContext({ 'x-admin-key': 'test-secret-key' })),
    ).toBe(true);
  });

  it('rejects missing or wrong credentials when key is configured', () => {
    process.env.ADMIN_API_KEY = 'test-secret-key';
    expect(() => guard.canActivate(makeContext({}))).toThrow(
      UnauthorizedException,
    );
    expect(() =>
      guard.canActivate(makeContext({ authorization: 'Bearer wrong' })),
    ).toThrow(UnauthorizedException);
  });
});
