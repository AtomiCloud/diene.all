import { beforeAll, describe, it } from 'bun:test';
import should from 'should';
import {
  SignedConsoleAuthorizationExchange,
  SignedConsoleNativeAuthorizer,
} from '../../../src/console/authorization.ts';
import type { ConsoleClock, ConsoleRequestSecurity } from '../../../src/console/ports.ts';

class MutableClock implements ConsoleClock {
  value = new Date('2026-07-29T01:00:00.000Z');

  now(): Date {
    return new Date(this.value);
  }
}

class TokenIds implements ConsoleRequestSecurity {
  counter = 0;

  issueToken(): string {
    this.counter += 1;
    return `authorization-token-id-${this.counter}`;
  }

  equal(left: string, right: string): boolean {
    return left === right;
  }
}

const identity = {
  accountId: 'account-1',
  accountName: 'internal/default',
  accountKind: 'default-internal' as const,
};

const scope = {
  tenants: ['tenant-1', 'tenant-2'],
  landscapes: ['serving', 'castform'],
  capabilities: [
    'operations:read',
    'events:replay',
    'endpoints:replay',
    'endpoints:reenable',
    'retention:run',
  ] as const,
};

describe('signed console-native authorization', () => {
  let keyPair: CryptoKeyPair;

  beforeAll(async () => {
    keyPair = (await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, false, [
      'sign',
      'verify',
    ])) as CryptoKeyPair;
  });

  const makeBoundary = () => {
    const clock = new MutableClock();
    const common = {
      clock,
      keyId: 'console-key-01',
      issuer: 'https://mercury.example.test/console',
      audience: 'atomi-mercury-landscape-operations',
    };
    return {
      clock,
      exchange: new SignedConsoleAuthorizationExchange({
        ...common,
        signingKey: keyPair.privateKey,
        tokenIds: new TokenIds(),
        ttlSeconds: 30,
      }),
      authorizer: new SignedConsoleNativeAuthorizer({
        ...common,
        verifyingKey: keyPair.publicKey,
      }),
    };
  };

  it('binds session, account, tenant, landscape, and least-privilege capabilities', async () => {
    // Arrange
    const { exchange, authorizer } = makeBoundary();

    // Act
    const issued = await exchange.exchange({
      sessionId: 'session-12345678',
      identity,
      scope,
      requiredCapabilities: ['operations:read'],
      optionalCapabilities: ['events:replay', 'retention:run'],
    });
    if (!issued.ok) throw new Error('Expected authorization issuance');
    const authorized = await authorizer.authorize(`Bearer ${issued.value.token}`, {
      landscape: 'serving',
      tenant: 'tenant-2',
      capability: 'retention:run',
      accountId: 'account-1',
    });

    // Assert
    should(authorized.ok).equal(true);
    if (!authorized.ok) throw new Error('Expected native authorization');
    should(authorized.value.sessionId).equal('session-12345678');
    should(authorized.value.accountId).equal('account-1');
    should(authorized.value.scope.capabilities).deepEqual(['operations:read', 'events:replay', 'retention:run']);
    should(issued.value.token).not.containEql('account-1');
  });

  it('fails closed on token tampering and expiry', async () => {
    // Arrange
    const { clock, exchange, authorizer } = makeBoundary();
    const issued = await exchange.exchange({
      sessionId: 'session-12345678',
      identity,
      scope,
      requiredCapabilities: ['operations:read'],
      optionalCapabilities: [],
    });
    if (!issued.ok) throw new Error('Expected authorization issuance');

    // Act
    const tampered = await authorizer.authorize(`Bearer ${issued.value.token}x`, {
      landscape: 'serving',
      capability: 'operations:read',
    });
    clock.value = new Date('2026-07-29T01:00:31.000Z');
    const expired = await authorizer.authorize(`Bearer ${issued.value.token}`, {
      landscape: 'serving',
      capability: 'operations:read',
    });

    // Assert
    should(tampered.ok).equal(false);
    should(expired.ok).equal(false);
    if (tampered.ok || expired.ok) throw new Error('Expected authorization rejection');
    should(tampered.error.kind).equal('unauthenticated');
    should(expired.error.kind).equal('unauthenticated');
  });

  it('rejects account, tenant, landscape, and capability scope mismatches', async () => {
    // Arrange
    const { exchange, authorizer } = makeBoundary();
    const issued = await exchange.exchange({
      sessionId: 'session-12345678',
      identity,
      scope,
      requiredCapabilities: ['operations:read'],
      optionalCapabilities: [],
    });
    if (!issued.ok) throw new Error('Expected authorization issuance');
    const authorization = `Bearer ${issued.value.token}`;

    // Act
    const results = await Promise.all([
      authorizer.authorize(authorization, {
        landscape: 'other',
        capability: 'operations:read',
      }),
      authorizer.authorize(authorization, {
        landscape: 'serving',
        tenant: 'tenant-other',
        capability: 'operations:read',
      }),
      authorizer.authorize(authorization, {
        landscape: 'serving',
        capability: 'events:replay',
      }),
      authorizer.authorize(authorization, {
        landscape: 'serving',
        capability: 'operations:read',
        accountId: 'account-other',
      }),
    ]);

    // Assert
    for (const result of results) {
      should(result.ok).equal(false);
      if (result.ok) throw new Error('Expected scope rejection');
      should(result.error.kind).equal('forbidden');
    }
  });

  it('does not mint retention:run when it is absent from the session scope', async () => {
    // Arrange
    const { exchange } = makeBoundary();

    // Act
    const result = await exchange.exchange({
      sessionId: 'session-12345678',
      identity,
      scope: { ...scope, capabilities: ['operations:read'] },
      requiredCapabilities: ['retention:run'],
      optionalCapabilities: [],
    });

    // Assert
    should(result.ok).equal(false);
    if (result.ok) throw new Error('Expected capability rejection');
    should(result.error.kind).equal('forbidden');
  });
});
