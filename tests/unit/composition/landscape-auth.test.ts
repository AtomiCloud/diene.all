import { describe, expect, test } from 'bun:test';
import { ConsoleLandscapeOperationsAuthenticator } from '../../../src/composition/landscape-auth.ts';
import type {
  ConsoleAuthorizedPrincipal,
  ConsoleCapability,
  ConsoleNativeAuthorizer,
  ConsoleResult,
} from '../../../src/console/index.ts';

const principal: ConsoleAuthorizedPrincipal = {
  tokenId: 'token-id',
  sessionId: 'session-id',
  accountId: 'account-id',
  issuedAt: new Date('2026-07-29T00:00:00Z'),
  expiresAt: new Date('2026-07-29T00:01:00Z'),
  scope: {
    tenants: ['tenant-a'],
    landscapes: ['lapras'],
    capabilities: ['operations:read', 'events:replay'],
  },
};

class CapabilityAuthorizer implements ConsoleNativeAuthorizer {
  constructor(readonly granted: readonly ConsoleCapability[]) {}

  async authorize(
    authorization: string | undefined,
    requirement: { readonly landscape: string; readonly capability: ConsoleCapability },
  ): Promise<ConsoleResult<ConsoleAuthorizedPrincipal>> {
    return authorization === 'Bearer signed' &&
      requirement.landscape === 'lapras' &&
      this.granted.includes(requirement.capability)
      ? { ok: true, value: principal }
      : {
          ok: false,
          error: { kind: 'forbidden', title: 'rejected', detail: 'outside scope' },
        };
  }
}

describe('landscape operations authentication composition', () => {
  test('projects only verified bearer capabilities into the local API', async () => {
    const authenticator = new ConsoleLandscapeOperationsAuthenticator(
      'lapras',
      new CapabilityAuthorizer(['operations:read', 'events:replay']),
    );

    const result = await authenticator.authenticate(
      new Request('https://mercury.example/internal/landscape/v1/health', {
        headers: { authorization: 'Bearer signed' },
      }),
    );

    expect(await result.isOk()).toBe(true);
    expect(await result.unwrap()).toEqual({
      subject: 'session-id',
      accountId: 'account-id',
      tenants: ['tenant-a'],
      capabilities: ['operations:read', 'events:replay'],
    });
  });

  test('fails closed when no capability can be authenticated', async () => {
    const authenticator = new ConsoleLandscapeOperationsAuthenticator('lapras', new CapabilityAuthorizer([]));

    const result = await authenticator.authenticate(new Request('https://mercury.example/health'));

    expect(await result.isErr()).toBe(true);
    expect((await result.unwrapErr()).code).toBe('invalid');
  });
});
