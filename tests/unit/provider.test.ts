import { describe, expect, it } from 'bun:test';
import { ACCESS_TOKEN_LIFETIME, REFRESH_TOKEN_LIFETIME } from '../../src/lib/provider';

describe('AuthProvider lifetimes', () => {
  it('publishes the canonical access and refresh token durations', () => {
    expect(ACCESS_TOKEN_LIFETIME.toString()).toBe('PT10M');
    expect(REFRESH_TOKEN_LIFETIME.toString()).toBe('P14D');
  });
});
