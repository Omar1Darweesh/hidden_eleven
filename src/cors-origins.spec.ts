import { getAllowedOrigins } from './cors-origins';

describe('getAllowedOrigins', () => {
  const original = process.env.ALLOWED_ORIGINS;

  afterEach(() => {
    if (original === undefined) delete process.env.ALLOWED_ORIGINS;
    else process.env.ALLOWED_ORIGINS = original;
  });

  it('defaults to localhost:3000 when unset', () => {
    delete process.env.ALLOWED_ORIGINS;
    expect(getAllowedOrigins()).toEqual(['http://localhost:3000']);
  });

  it('defaults to localhost:3000 when set to an empty string', () => {
    process.env.ALLOWED_ORIGINS = '   ';
    expect(getAllowedOrigins()).toEqual(['http://localhost:3000']);
  });

  it('parses a single configured origin', () => {
    process.env.ALLOWED_ORIGINS = 'https://app.example.com';
    expect(getAllowedOrigins()).toEqual(['https://app.example.com']);
  });

  it('parses multiple comma-separated origins, trimming whitespace and dropping empties', () => {
    process.env.ALLOWED_ORIGINS = ' https://app.example.com ,https://staging.example.com,,';
    expect(getAllowedOrigins()).toEqual([
      'https://app.example.com',
      'https://staging.example.com',
    ]);
  });
});
