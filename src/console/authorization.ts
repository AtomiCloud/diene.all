import { jwtVerify, SignJWT } from 'jose';
import type {
  ConsoleAuthorizationScope,
  ConsoleAuthorizedPrincipal,
  ConsoleCapability,
  ConsoleFailure,
  ConsoleNativeAuthorization,
  ConsoleResult,
} from './model.ts';
import type {
  ConsoleAuthorizationExchange,
  ConsoleClock,
  ConsoleNativeAuthorizer,
  ConsoleRequestSecurity,
} from './ports.ts';

const CAPABILITIES: readonly ConsoleCapability[] = [
  'operations:read',
  'events:replay',
  'endpoints:replay',
  'endpoints:reenable',
  'retention:run',
];
const MAX_BEARER_LENGTH = 8_192;

const failure = (kind: ConsoleFailure['kind'], title: string, detail: string): ConsoleResult<never> => ({
  ok: false,
  error: { kind, title, detail },
});

const copyScope = (scope: ConsoleAuthorizationScope): ConsoleAuthorizationScope => ({
  tenants: scope.tenants === '*' ? '*' : [...scope.tenants],
  landscapes: scope.landscapes === '*' ? '*' : [...scope.landscapes],
  capabilities: [...scope.capabilities],
});

const scopeValue = (value: unknown): '*' | readonly string[] | undefined => {
  if (value === '*') return '*';
  if (
    Array.isArray(value) &&
    value.length <= 1_024 &&
    value.every(entry => typeof entry === 'string' && entry.length > 0 && entry.length <= 256)
  ) {
    return [...new Set(value)];
  }
  return undefined;
};

const capabilityValue = (value: unknown): readonly ConsoleCapability[] | undefined => {
  if (
    !Array.isArray(value) ||
    value.some(entry => typeof entry !== 'string' || !CAPABILITIES.includes(entry as ConsoleCapability))
  ) {
    return undefined;
  }
  return [...new Set(value as ConsoleCapability[])];
};

const includesScope = (scope: '*' | readonly string[], expected: string): boolean =>
  scope === '*' || scope.includes(expected);

interface AuthorizationTokenConfiguration {
  readonly clock: ConsoleClock;
  readonly keyId: string;
  readonly issuer: string;
  readonly audience: string;
}

export interface SignedConsoleAuthorizationExchangeOptions extends AuthorizationTokenConfiguration {
  readonly signingKey: CryptoKey;
  readonly tokenIds: ConsoleRequestSecurity;
  readonly ttlSeconds: number;
}

export class SignedConsoleAuthorizationExchange implements ConsoleAuthorizationExchange {
  readonly #options: SignedConsoleAuthorizationExchangeOptions;

  constructor(options: SignedConsoleAuthorizationExchangeOptions) {
    if (
      options.signingKey.type !== 'private' ||
      options.signingKey.algorithm.name !== 'ECDSA' ||
      !options.signingKey.usages.includes('sign')
    ) {
      throw new Error('Console authorization signing key must be a private ECDSA signing key');
    }
    if (
      !/^[A-Za-z0-9._-]{8,128}$/.test(options.keyId) ||
      options.issuer.length === 0 ||
      options.audience.length === 0 ||
      !Number.isSafeInteger(options.ttlSeconds) ||
      options.ttlSeconds < 15 ||
      options.ttlSeconds > 300
    ) {
      throw new Error('Console authorization token configuration is invalid');
    }
    this.#options = options;
  }

  async exchange(request: {
    readonly sessionId: string;
    readonly identity: { readonly accountId: string };
    readonly scope: ConsoleAuthorizationScope;
    readonly requiredCapabilities: readonly ConsoleCapability[];
    readonly optionalCapabilities: readonly ConsoleCapability[];
  }): Promise<ConsoleResult<ConsoleNativeAuthorization>> {
    const allowed = request.scope.capabilities;
    if (request.requiredCapabilities.some(capability => !allowed.includes(capability))) {
      return failure(
        'forbidden',
        'Capability unavailable',
        'The account does not hold a capability required for this operation.',
      );
    }
    const capabilities = [
      ...request.requiredCapabilities,
      ...request.optionalCapabilities.filter(capability => allowed.includes(capability)),
    ].filter((capability, index, values) => values.indexOf(capability) === index);
    const scope: ConsoleAuthorizationScope = {
      tenants: request.scope.tenants === '*' ? '*' : [...request.scope.tenants],
      landscapes: request.scope.landscapes === '*' ? '*' : [...request.scope.landscapes],
      capabilities,
    };
    const issuedAt = Math.floor(this.#options.clock.now().getTime() / 1_000);
    const expiresAt = issuedAt + this.#options.ttlSeconds;
    const token = await new SignJWT({
      sid: request.sessionId,
      tenants: scope.tenants,
      landscapes: scope.landscapes,
      capabilities: scope.capabilities,
    })
      .setProtectedHeader({
        alg: 'ES256',
        kid: this.#options.keyId,
        typ: 'atomi-mercury-console+jwt',
      })
      .setIssuer(this.#options.issuer)
      .setAudience(this.#options.audience)
      .setSubject(request.identity.accountId)
      .setJti(this.#options.tokenIds.issueToken(18))
      .setIssuedAt(issuedAt)
      .setExpirationTime(expiresAt)
      .sign(this.#options.signingKey);

    return {
      ok: true,
      value: {
        scheme: 'Bearer',
        token,
        expiresAt: new Date(expiresAt * 1_000),
        accountId: request.identity.accountId,
        sessionId: request.sessionId,
        scope,
      },
    };
  }
}

export interface SignedConsoleNativeAuthorizerOptions extends AuthorizationTokenConfiguration {
  readonly verifyingKey: CryptoKey;
}

export class SignedConsoleNativeAuthorizer implements ConsoleNativeAuthorizer {
  readonly #options: SignedConsoleNativeAuthorizerOptions;

  constructor(options: SignedConsoleNativeAuthorizerOptions) {
    if (
      options.verifyingKey.type !== 'public' ||
      options.verifyingKey.algorithm.name !== 'ECDSA' ||
      !options.verifyingKey.usages.includes('verify')
    ) {
      throw new Error('Console authorization verifying key must be a public ECDSA verifying key');
    }
    if (
      !/^[A-Za-z0-9._-]{8,128}$/.test(options.keyId) ||
      options.issuer.length === 0 ||
      options.audience.length === 0
    ) {
      throw new Error('Console authorization verifier configuration is invalid');
    }
    this.#options = options;
  }

  async authorize(
    authorization: string | undefined,
    requirement: {
      readonly landscape: string;
      readonly capability: ConsoleCapability;
      readonly tenant?: string;
      readonly accountId?: string;
    },
  ): Promise<ConsoleResult<ConsoleAuthorizedPrincipal>> {
    const match = /^Bearer ([^\s]+)$/.exec(authorization ?? '');
    if (match?.[1] === undefined || match[1].length > MAX_BEARER_LENGTH) {
      return failure('unauthenticated', 'Native authorization required', 'A valid console-native bearer is required.');
    }
    try {
      const verified = await jwtVerify(match[1], this.#options.verifyingKey, {
        algorithms: ['ES256'],
        issuer: this.#options.issuer,
        audience: this.#options.audience,
        currentDate: this.#options.clock.now(),
      });
      if (
        verified.protectedHeader.kid !== this.#options.keyId ||
        verified.protectedHeader.typ !== 'atomi-mercury-console+jwt'
      ) {
        return failure('unauthenticated', 'Native authorization rejected', 'The console-native bearer is invalid.');
      }
      const tenants = scopeValue(verified.payload.tenants);
      const landscapes = scopeValue(verified.payload.landscapes);
      const capabilities = capabilityValue(verified.payload.capabilities);
      const { sub, jti, sid, iat, exp } = verified.payload;
      const nowSeconds = Math.floor(this.#options.clock.now().getTime() / 1_000);
      if (
        tenants === undefined ||
        landscapes === undefined ||
        capabilities === undefined ||
        typeof sub !== 'string' ||
        typeof jti !== 'string' ||
        typeof sid !== 'string' ||
        typeof iat !== 'number' ||
        typeof exp !== 'number' ||
        exp <= iat ||
        iat > nowSeconds
      ) {
        return failure('unauthenticated', 'Native authorization rejected', 'The console-native bearer is invalid.');
      }
      const scope: ConsoleAuthorizationScope = {
        tenants,
        landscapes,
        capabilities,
      };
      if (
        !includesScope(scope.landscapes, requirement.landscape) ||
        !scope.capabilities.includes(requirement.capability) ||
        (requirement.tenant !== undefined && !includesScope(scope.tenants, requirement.tenant)) ||
        (requirement.accountId !== undefined && requirement.accountId !== sub)
      ) {
        return failure(
          'forbidden',
          'Native authorization scope rejected',
          'The console-native bearer does not cover this operation.',
        );
      }
      return {
        ok: true,
        value: {
          tokenId: jti,
          sessionId: sid,
          accountId: sub,
          issuedAt: new Date(iat * 1_000),
          expiresAt: new Date(exp * 1_000),
          scope: copyScope(scope),
        },
      };
    } catch {
      return failure(
        'unauthenticated',
        'Native authorization rejected',
        'The console-native bearer is invalid or expired.',
      );
    }
  }
}
