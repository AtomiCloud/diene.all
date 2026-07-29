import { describe, it } from 'bun:test';
import should from 'should';
import type { ConsoleAuthorizationScope, ConsoleIdentity, ConsoleSessionRecord } from '../../../src/console/model.ts';
import type { ConsoleSessionCryptography, ConsoleSessionRepository } from '../../../src/console/ports.ts';
import { ConsoleSessionManager, WebCryptoConsoleSessionCryptography } from '../../../src/console/session.ts';

class MemorySessionRepository implements ConsoleSessionRepository {
  readonly records = new Map<string, ConsoleSessionRecord>();
  rotateAllowed = true;

  async find(tokenHash: string): Promise<ConsoleSessionRecord | undefined> {
    return this.records.get(tokenHash);
  }

  async create(record: ConsoleSessionRecord): Promise<boolean> {
    if (this.records.has(record.tokenHash)) return false;
    this.records.set(record.tokenHash, record);
    return true;
  }

  async touch(current: ConsoleSessionRecord, replacement: ConsoleSessionRecord): Promise<boolean> {
    if (this.records.get(current.tokenHash) !== current) return false;
    this.records.set(replacement.tokenHash, replacement);
    return true;
  }

  async rotate(currentTokenHash: string, replacement: ConsoleSessionRecord): Promise<boolean> {
    if (!this.rotateAllowed || !this.records.has(currentTokenHash)) return false;
    this.records.delete(currentTokenHash);
    this.records.set(replacement.tokenHash, replacement);
    return true;
  }

  async delete(tokenHash: string): Promise<void> {
    this.records.delete(tokenHash);
  }
}

class DeterministicCryptography implements ConsoleSessionCryptography {
  counter = 0;

  randomToken(byteLength: number): string {
    this.counter += 1;
    return `token-${byteLength}-${String(this.counter).padStart(32, '0')}`;
  }

  async hashToken(token: string): Promise<string> {
    return `hash:${token}`;
  }

  async deriveCsrfToken(token: string): Promise<string> {
    return `csrf:${token}`;
  }
}

const identity: ConsoleIdentity = {
  accountId: 'account-1',
  accountName: 'internal/default',
  accountKind: 'default-internal',
};

const scope: ConsoleAuthorizationScope = {
  tenants: ['tenant-1'],
  landscapes: ['serving'],
  capabilities: ['operations:read', 'events:replay'],
};

const now = new Date('2026-07-29T00:00:00.000Z');

const makeManager = (
  repository = new MemorySessionRepository(),
  cryptography = new DeterministicCryptography(),
): {
  readonly repository: MemorySessionRepository;
  readonly cryptography: DeterministicCryptography;
  readonly manager: ConsoleSessionManager;
} => ({
  repository,
  cryptography,
  manager: new ConsoleSessionManager(repository, cryptography, {
    idleTtlSeconds: 600,
    absoluteTtlSeconds: 3_600,
    rotationIntervalSeconds: 300,
  }),
});

describe('ConsoleSessionManager', () => {
  it('creates an opaque, idle-bounded session without storing the bearer cookie', async () => {
    // Arrange
    const { manager, repository } = makeManager();

    // Act
    const ticket = await manager.create(identity, scope, now);
    const record = [...repository.records.values()][0];

    // Assert
    should(record).not.equal(undefined);
    should(record?.tokenHash).equal(`hash:${ticket.token}`);
    should(record?.tokenHash).not.equal(ticket.token);
    should(ticket.csrfToken).equal(`csrf:${ticket.token}`);
    should(ticket.requestCsrfToken).equal(ticket.csrfToken);
    should(ticket.rotated).equal(false);
    should(ticket.scope).deepEqual(scope);
    should(record?.scope).deepEqual(scope);
    should(ticket.expiresAt.toISOString()).equal('2026-07-29T00:10:00.000Z');
    should(record?.absoluteExpiresAt.toISOString()).equal('2026-07-29T01:00:00.000Z');
  });

  it('slides idle expiry while preserving the same session before rotation', async () => {
    // Arrange
    const { manager, repository } = makeManager();
    const created = await manager.create(identity, scope, now);

    // Act
    const resolved = await manager.resolve(created.token, new Date('2026-07-29T00:04:00.000Z'));
    const record = [...repository.records.values()][0];

    // Assert
    should(resolved.kind).equal('active');
    if (resolved.kind !== 'active') throw new Error('Expected active session');
    should(resolved.ticket.token).equal(created.token);
    should(resolved.ticket.rotated).equal(false);
    should(record?.idleExpiresAt.toISOString()).equal('2026-07-29T00:14:00.000Z');
    should(record?.absoluteExpiresAt.toISOString()).equal('2026-07-29T01:00:00.000Z');
  });

  it('expires and removes a session at its idle boundary', async () => {
    // Arrange
    const { manager, repository } = makeManager();
    const created = await manager.create(identity, scope, now);

    // Act
    const resolved = await manager.resolve(created.token, new Date('2026-07-29T00:10:00.000Z'));

    // Assert
    should(resolved.kind).equal('expired');
    should(repository.records.size).equal(0);
  });

  it('rotates atomically and accepts the CSRF token bound to the incoming request', async () => {
    // Arrange
    const { manager, repository } = makeManager();
    const created = await manager.create(identity, scope, now);

    // Act
    const resolved = await manager.resolve(created.token, new Date('2026-07-29T00:05:00.000Z'));

    // Assert
    should(resolved.kind).equal('active');
    if (resolved.kind !== 'active') throw new Error('Expected active session');
    should(resolved.ticket.rotated).equal(true);
    should(resolved.ticket.token).not.equal(created.token);
    should(resolved.ticket.requestCsrfToken).equal(`csrf:${created.token}`);
    should(resolved.ticket.csrfToken).equal(`csrf:${resolved.ticket.token}`);
    should(repository.records.has(`hash:${created.token}`)).equal(false);
    should(repository.records.has(`hash:${resolved.ticket.token}`)).equal(true);
    should((await manager.resolve(created.token, new Date('2026-07-29T00:05:01.000Z'))).kind).equal('invalid');
  });

  it('rejects a lost rotation race without creating a second live session', async () => {
    // Arrange
    const repository = new MemorySessionRepository();
    const { manager } = makeManager(repository);
    const created = await manager.create(identity, scope, now);
    repository.rotateAllowed = false;

    // Act
    const resolved = await manager.resolve(created.token, new Date('2026-07-29T00:05:00.000Z'));

    // Assert
    should(resolved.kind).equal('invalid');
    should(repository.records.size).equal(1);
    should(repository.records.has(`hash:${created.token}`)).equal(true);
  });

  it('revokes the server-side session addressed by the cookie token', async () => {
    // Arrange
    const { manager, repository } = makeManager();
    const created = await manager.create(identity, scope, now);

    // Act
    await manager.revoke(created.token);

    // Assert
    should(repository.records.size).equal(0);
    should((await manager.resolve(created.token, now)).kind).equal('invalid');
  });

  it('rejects policies that weaken the configured session boundaries', () => {
    // Arrange
    const repository = new MemorySessionRepository();
    const cryptography = new DeterministicCryptography();

    // Act
    const construct = (): ConsoleSessionManager =>
      new ConsoleSessionManager(repository, cryptography, {
        idleTtlSeconds: 3_601,
        absoluteTtlSeconds: 3_600,
        rotationIntervalSeconds: 300,
      });

    // Assert
    should(construct).throw('Console session policy is invalid');
  });
});

describe('WebCryptoConsoleSessionCryptography', () => {
  it('derives stable hashes and distinct HMAC-bound CSRF tokens', async () => {
    // Arrange
    const cryptography = new WebCryptoConsoleSessionCryptography(new Uint8Array(32).fill(17));

    // Act
    const firstHash = await cryptography.hashToken('opaque-session-token');
    const secondHash = await cryptography.hashToken('opaque-session-token');
    const firstCsrf = await cryptography.deriveCsrfToken('opaque-session-token');
    const secondCsrf = await cryptography.deriveCsrfToken('different-session-token');

    // Assert
    should(firstHash).equal(secondHash);
    should(firstCsrf).not.equal(secondCsrf);
    should(cryptography.randomToken(32).length).be.greaterThan(40);
  });
});
