import { describe, it } from 'bun:test';
import should from 'should';
import { MercuryManagementConsoleGateway } from '../../../src/console/management-gateway.ts';
import type { ConsoleLoginRateLimiter } from '../../../src/console/ports.ts';
import { InMemoryManagementRepository } from '../../../src/management/memory-repository.ts';
import { ManagementService } from '../../../src/management/service.ts';
import type { LandscapeEventSource } from '../../../src/management/types.ts';

class FakeRateLimiter implements ConsoleLoginRateLimiter {
  readonly attempts: string[] = [];
  readonly resets: string[] = [];
  allowed = true;

  async attempt(
    accountName: string,
  ): Promise<{ readonly allowed: true } | { readonly allowed: false; readonly retryAfterSeconds: number }> {
    this.attempts.push(accountName);
    return this.allowed ? { allowed: true } : { allowed: false, retryAfterSeconds: 30 };
  }

  async reset(accountName: string): Promise<void> {
    this.resets.push(accountName);
  }
}

class FaultInjectingManagementRepository extends InMemoryManagementRepository {
  injectedSources: readonly LandscapeEventSource[] = [];

  override async listLandscapeEventSources(accountId: string): Promise<readonly LandscapeEventSource[]> {
    const sources = await super.listLandscapeEventSources(accountId);
    return [...sources, ...this.injectedSources];
  }
}

const harness = async (repository: InMemoryManagementRepository = new InMemoryManagementRepository()) => {
  let nextId = 0;
  const service = new ManagementService(repository, {
    clock: () => new Date('2026-07-29T01:00:00.000Z'),
    idFactory: () => `00000000-0000-4000-8000-${(++nextId).toString().padStart(12, '0')}`,
    tokenFactory: () => `generated-native-token-${nextId}`,
  });
  const provisioned = await service.provisionDefaultInternalAccount('native-management-token-secret');
  const principal = await service.authenticateBearer('Bearer native-management-token-secret');
  const tenant = await service.createOrAdoptTenant({
    accountId: provisioned.account.id,
    name: 'internal/nitroso',
    intakeSlug: 'nitroso',
    source: 'cr',
    homeVlandscape: 'serving',
  });
  await service.saveLandscapeEventSource(principal, {
    landscape: 'serving',
    queryUrl: 'https://serving.example.test/query',
    replayUrl: 'https://serving.example.test/actions',
    credentialPointer: '/mercury-serving-operations',
    enabled: true,
  });
  const limiter = new FakeRateLimiter();
  return {
    gateway: new MercuryManagementConsoleGateway(service, limiter),
    limiter,
    principal,
    provisioned,
    repository,
    service,
    tenant,
  };
};

describe('MercuryManagementConsoleGateway', () => {
  it('authenticates the native account and returns only non-secret identity plus ID scope', async () => {
    // Arrange
    const { gateway, limiter, provisioned, tenant } = await harness();

    // Act
    const result = await gateway.authenticate({
      accountName: 'internal/default',
      bearerCredential: 'native-management-token-secret',
    });

    // Assert
    should(result.kind).equal('authenticated');
    if (result.kind !== 'authenticated') throw new Error('Expected native account authentication');
    should(result.identity).deepEqual({
      accountId: provisioned.account.id,
      accountName: 'internal/default',
      accountKind: 'default-internal',
    });
    should(result.scope.tenants).deepEqual([tenant.id]);
    should(result.scope.landscapes).deepEqual(['serving']);
    should(result.scope.capabilities).deepEqual([
      'operations:read',
      'events:replay',
      'endpoints:replay',
      'endpoints:reenable',
      'retention:run',
    ]);
    should(JSON.stringify(result)).not.containEql('native-management-token-secret');
    should(limiter.resets).deepEqual(['internal/default']);
  });

  it('keeps account mismatch, invalid bearer, and limiter rejection generic', async () => {
    // Arrange
    const { gateway, limiter } = await harness();

    // Act
    const mismatch = await gateway.authenticate({
      accountName: 'internal/not-default',
      bearerCredential: 'native-management-token-secret',
    });
    const invalid = await gateway.authenticate({
      accountName: 'internal/default',
      bearerCredential: 'invalid-management-token',
    });
    limiter.allowed = false;
    const limited = await gateway.authenticate({
      accountName: 'internal/default',
      bearerCredential: 'native-management-token-secret',
    });

    // Assert
    should(mismatch).deepEqual({ kind: 'rejected' });
    should(invalid).deepEqual({ kind: 'rejected' });
    should(limited).deepEqual({ kind: 'rate-limited', retryAfterSeconds: 30 });
    should(limiter.resets).have.length(0);
  });

  it('maps retention:run only from an explicit management scope or wildcard', async () => {
    // Arrange
    const { gateway, provisioned, service } = await harness();
    await service.issueManagementCredential(
      provisioned.account.id,
      undefined,
      ['landscapes:read'],
      'operations-read-only-token',
    );
    await service.issueManagementCredential(
      provisioned.account.id,
      undefined,
      ['landscapes:read', 'retention:run'],
      'operations-retention-token',
    );

    // Act
    const readOnly = await gateway.authenticate({
      accountName: 'internal/default',
      bearerCredential: 'operations-read-only-token',
    });
    const retention = await gateway.authenticate({
      accountName: 'internal/default',
      bearerCredential: 'operations-retention-token',
    });

    // Assert
    should(readOnly.kind).equal('authenticated');
    should(retention.kind).equal('authenticated');
    if (readOnly.kind !== 'authenticated' || retention.kind !== 'authenticated') {
      throw new Error('Expected scoped console authentication');
    }
    should(readOnly.scope.capabilities).deepEqual(['operations:read']);
    should(retention.scope.capabilities).deepEqual(['operations:read', 'retention:run']);
  });

  it('rejects authentication if the account-scoped repository crosses a landscape source boundary', async () => {
    // Arrange
    const repository = new FaultInjectingManagementRepository();
    const { gateway, limiter } = await harness(repository);
    repository.injectedSources = [
      {
        accountId: 'victim-account-id',
        landscape: 'attacker',
        queryUrl: 'https://attacker.example.test/query',
        replayUrl: 'https://attacker.example.test/actions',
        credentialPointer: '/mercury-attacker-operations',
        enabled: true,
        updatedAt: new Date('2026-07-29T01:00:00.000Z'),
      },
    ];

    // Act
    const result = await gateway.authenticate({
      accountName: 'internal/default',
      bearerCredential: 'native-management-token-secret',
    });

    // Assert
    should(result).deepEqual({ kind: 'rejected' });
    should(limiter.resets).have.length(0);
  });

  it('returns enabled scoped source URLs without exposing credential pointers', async () => {
    // Arrange
    const { gateway, provisioned } = await harness();
    const authorization = {
      scheme: 'Bearer' as const,
      token: 'short-lived-console-authorization',
      expiresAt: new Date('2026-07-29T01:01:00.000Z'),
      accountId: provisioned.account.id,
      sessionId: 'session-12345678',
      scope: {
        tenants: '*' as const,
        landscapes: ['serving'],
        capabilities: ['operations:read'] as const,
      },
    };

    // Act
    const sources = await gateway.landscapeSources({
      accountId: provisioned.account.id,
      authorization,
    });

    // Assert
    should(sources.ok).equal(true);
    if (!sources.ok) throw new Error('Expected enabled source');
    should(sources.value).deepEqual([
      {
        trustKind: 'account-owned',
        accountId: provisioned.account.id,
        landscape: 'serving',
        queryUrl: 'https://serving.example.test/query',
        queryOrigin: 'https://serving.example.test',
        replayUrl: 'https://serving.example.test/actions',
        replayOrigin: 'https://serving.example.test',
        enabled: true,
      },
    ]);
    should(JSON.stringify(sources.value)).not.containEql('credentialPointer');
  });

  it('rejects an unsafe configured HTTPS source before fan-in', async () => {
    // Arrange
    const repository = new FaultInjectingManagementRepository();
    const { gateway, provisioned } = await harness(repository);
    repository.injectedSources = [
      {
        accountId: provisioned.account.id,
        landscape: 'castform',
        queryUrl: 'https://user:password@castform.example.test/query',
        replayUrl: 'https://castform.example.test/actions?secret=value',
        credentialPointer: '/mercury-castform-operations',
        enabled: true,
        updatedAt: new Date('2026-07-29T01:00:00.000Z'),
      },
    ];

    // Act
    const result = await gateway.landscapeSources({
      accountId: provisioned.account.id,
      authorization: {
        scheme: 'Bearer',
        token: 'short-lived-console-authorization',
        expiresAt: new Date('2026-07-29T01:01:00.000Z'),
        accountId: provisioned.account.id,
        sessionId: 'session-12345678',
        scope: {
          tenants: '*',
          landscapes: '*',
          capabilities: ['operations:read'],
        },
      },
    });

    // Assert
    should(result.ok).equal(false);
    if (result.ok) throw new Error('Expected unsafe source rejection');
    should(result.error.kind).equal('unavailable');
    should(result.error.detail).not.containEql('password');
    should(result.error.detail).not.containEql('secret=value');
  });
});
