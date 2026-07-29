import type {
  ConsoleAuthorizationScope,
  ConsoleIdentity,
  ConsoleSessionRecord,
  ConsoleSessionResolution,
  ConsoleSessionTicket,
} from './model.ts';
import type { ConsoleSessionCryptography, ConsoleSessionRepository, ConsoleSessions } from './ports.ts';

export interface ConsoleSessionPolicy {
  readonly idleTtlSeconds: number;
  readonly absoluteTtlSeconds: number;
  readonly rotationIntervalSeconds: number;
}

const earliest = (left: Date, right: Date): Date => (left.getTime() <= right.getTime() ? left : right);

const plusSeconds = (value: Date, seconds: number): Date => new Date(value.getTime() + seconds * 1_000);

const copyIdentity = (identity: ConsoleIdentity): ConsoleIdentity => ({ ...identity });

const copyScope = (scope: ConsoleAuthorizationScope): ConsoleAuthorizationScope => ({
  tenants: scope.tenants === '*' ? '*' : [...scope.tenants],
  landscapes: scope.landscapes === '*' ? '*' : [...scope.landscapes],
  capabilities: [...scope.capabilities],
});

interface IssuedSession {
  readonly record: ConsoleSessionRecord;
  readonly ticket: ConsoleSessionTicket;
}

const issueSession = async (
  cryptography: ConsoleSessionCryptography,
  policy: ConsoleSessionPolicy,
  identity: ConsoleIdentity,
  scope: ConsoleAuthorizationScope,
  createdAt: Date,
  now: Date,
  absoluteExpiresAt: Date,
  rotated: boolean,
  previousToken: string | undefined,
): Promise<IssuedSession> => {
  const token = cryptography.randomToken(32);
  const tokenHash = await cryptography.hashToken(token);
  const idleExpiresAt = earliest(plusSeconds(now, policy.idleTtlSeconds), absoluteExpiresAt);
  const rotateAt = earliest(plusSeconds(now, policy.rotationIntervalSeconds), absoluteExpiresAt);
  const record: ConsoleSessionRecord = {
    id: cryptography.randomToken(18),
    revision: 0,
    tokenHash,
    identity: copyIdentity(identity),
    scope: copyScope(scope),
    createdAt: new Date(createdAt),
    lastSeenAt: new Date(now),
    idleExpiresAt,
    absoluteExpiresAt: new Date(absoluteExpiresAt),
    rotateAt,
  };
  const csrfToken = await cryptography.deriveCsrfToken(token);
  const requestCsrfToken = previousToken === undefined ? csrfToken : await cryptography.deriveCsrfToken(previousToken);

  return {
    record,
    ticket: {
      token,
      csrfToken,
      requestCsrfToken,
      sessionId: record.id,
      identity: copyIdentity(identity),
      scope: copyScope(scope),
      expiresAt: new Date(idleExpiresAt),
      rotated,
    },
  };
};

export class ConsoleSessionManager implements ConsoleSessions {
  readonly #repository: ConsoleSessionRepository;
  readonly #cryptography: ConsoleSessionCryptography;
  readonly #policy: ConsoleSessionPolicy;

  constructor(
    repository: ConsoleSessionRepository,
    cryptography: ConsoleSessionCryptography,
    policy: ConsoleSessionPolicy,
  ) {
    if (
      !Number.isSafeInteger(policy.idleTtlSeconds) ||
      !Number.isSafeInteger(policy.absoluteTtlSeconds) ||
      !Number.isSafeInteger(policy.rotationIntervalSeconds) ||
      policy.idleTtlSeconds <= 0 ||
      policy.absoluteTtlSeconds <= 0 ||
      policy.rotationIntervalSeconds <= 0 ||
      policy.idleTtlSeconds > policy.absoluteTtlSeconds ||
      policy.rotationIntervalSeconds > policy.absoluteTtlSeconds
    ) {
      throw new Error('Console session policy is invalid');
    }

    this.#repository = repository;
    this.#cryptography = cryptography;
    this.#policy = { ...policy };
  }

  async create(identity: ConsoleIdentity, scope: ConsoleAuthorizationScope, now: Date): Promise<ConsoleSessionTicket> {
    const absoluteExpiresAt = plusSeconds(now, this.#policy.absoluteTtlSeconds);
    for (let attempt = 0; attempt < 3; attempt += 1) {
      const issued = await issueSession(
        this.#cryptography,
        this.#policy,
        identity,
        scope,
        now,
        now,
        absoluteExpiresAt,
        false,
        undefined,
      );
      if (await this.#repository.create(issued.record)) {
        return issued.ticket;
      }
    }
    throw new Error('Unable to allocate a unique console session token');
  }

  async resolve(token: string, now: Date): Promise<ConsoleSessionResolution> {
    if (token.length < 32 || token.length > 512) {
      return { kind: 'invalid' };
    }

    const tokenHash = await this.#cryptography.hashToken(token);
    const record = await this.#repository.find(tokenHash);
    if (record === undefined) {
      return { kind: 'invalid' };
    }

    if (now.getTime() >= record.absoluteExpiresAt.getTime() || now.getTime() >= record.idleExpiresAt.getTime()) {
      await this.#repository.delete(tokenHash);
      return { kind: 'expired' };
    }

    if (now.getTime() >= record.rotateAt.getTime()) {
      const issued = await issueSession(
        this.#cryptography,
        this.#policy,
        record.identity,
        record.scope,
        record.createdAt,
        now,
        record.absoluteExpiresAt,
        true,
        token,
      );
      if (!(await this.#repository.rotate(tokenHash, issued.record))) {
        return { kind: 'invalid' };
      }

      return {
        kind: 'active',
        ticket: issued.ticket,
      };
    }

    const idleExpiresAt = earliest(plusSeconds(now, this.#policy.idleTtlSeconds), record.absoluteExpiresAt);
    const touchedRecord: ConsoleSessionRecord = {
      ...record,
      revision: record.revision + 1,
      lastSeenAt: new Date(now),
      idleExpiresAt,
    };
    if (!(await this.#repository.touch(record, touchedRecord))) {
      return { kind: 'invalid' };
    }
    const csrfToken = await this.#cryptography.deriveCsrfToken(token);

    return {
      kind: 'active',
      ticket: {
        token,
        csrfToken,
        requestCsrfToken: csrfToken,
        sessionId: record.id,
        identity: copyIdentity(record.identity),
        scope: copyScope(record.scope),
        expiresAt: new Date(idleExpiresAt),
        rotated: false,
      },
    };
  }

  async revoke(token: string): Promise<void> {
    if (token.length < 32 || token.length > 512) {
      return;
    }

    await this.#repository.delete(await this.#cryptography.hashToken(token));
  }
}

const encodeBase64Url = (bytes: Uint8Array): string => Buffer.from(bytes).toString('base64url');

const encodeText = (value: string): Uint8Array => new TextEncoder().encode(value);

const toArrayBuffer = (bytes: Uint8Array): ArrayBuffer => {
  const buffer = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(buffer).set(bytes);
  return buffer;
};

export class WebCryptoConsoleSessionCryptography implements ConsoleSessionCryptography {
  readonly #hmacSecret: Uint8Array;

  constructor(hmacSecret: Uint8Array) {
    if (hmacSecret.byteLength < 32) {
      throw new Error('Console session HMAC secret must contain at least 32 bytes');
    }

    this.#hmacSecret = Uint8Array.from(hmacSecret);
  }

  randomToken(byteLength: number): string {
    if (!Number.isSafeInteger(byteLength) || byteLength < 16 || byteLength > 128) {
      throw new Error('Console random token length is invalid');
    }

    return encodeBase64Url(crypto.getRandomValues(new Uint8Array(byteLength)));
  }

  async hashToken(token: string): Promise<string> {
    const digest = await crypto.subtle.digest('SHA-256', toArrayBuffer(encodeText(token)));
    return encodeBase64Url(new Uint8Array(digest));
  }

  async deriveCsrfToken(token: string): Promise<string> {
    const key = await crypto.subtle.importKey(
      'raw',
      toArrayBuffer(this.#hmacSecret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign'],
    );
    const signature = await crypto.subtle.sign('HMAC', key, toArrayBuffer(encodeText(`csrf:${token}`)));
    return encodeBase64Url(new Uint8Array(signature));
  }
}
