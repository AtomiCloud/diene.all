import type { z } from 'zod';
import {
  type AppleBackfillEvidence,
  type ArchiveLifecycleEvidence,
  type AtomicAcceptanceEvidence,
  appleBackfillEvidenceSchema,
  archiveLifecycleEvidenceSchema,
  atomicAcceptanceEvidenceSchema,
  type ConsoleJourneyEvidence,
  consoleJourneyEvidenceSchema,
  type DependencyEvidence,
  dependencyEvidenceSchema,
  type FanoutEvidence,
  fanoutEvidenceSchema,
  type GoogleSubscriptionEvidence,
  googleSubscriptionEvidenceSchema,
  type ProviderName,
  type ProviderVerificationEvidence,
  providerNames,
  providerVerificationMatrixSchema,
  type Route53LandingEvidence,
  route53LandingEvidenceSchema,
  type SignatureLifecycleEvidence,
  sessionEvidenceSchema,
  signatureLifecycleEvidenceSchema,
} from './evidence.ts';

const DEFAULT_TIMEOUT_MS = 10_000;
const MAX_TIMEOUT_MS = 300_000;
const MAX_RESPONSE_BYTES = 2 * 1024 * 1024;

type SitClientErrorCode = 'closed' | 'configuration' | 'http' | 'network' | 'protocol' | 'timeout';

export class MercurySitClientError extends Error {
  readonly code: SitClientErrorCode;

  constructor(code: SitClientErrorCode, message: string, options?: ErrorOptions) {
    super(message, options);
    this.name = 'MercurySitClientError';
    this.code = code;
  }
}

export interface MercuryTestStackFactoryInput {
  readonly environment: Readonly<Record<string, string | undefined>>;
  readonly requiredProviderFixtures: readonly ProviderName[];
}

export interface MercuryTestStack {
  close(): Promise<void>;
  inspectDependencies(): Promise<DependencyEvidence>;
  runProviderVerificationMatrix(): Promise<readonly ProviderVerificationEvidence[]>;
  runAtomicAcceptance(): Promise<AtomicAcceptanceEvidence>;
  runFanout(): Promise<FanoutEvidence>;
  runSignatureLifecycle(): Promise<SignatureLifecycleEvidence>;
  runConsoleJourney(): Promise<ConsoleJourneyEvidence>;
  runAppleBackfill(): Promise<AppleBackfillEvidence>;
  inspectGoogleSubscription(): Promise<GoogleSubscriptionEvidence>;
  runArchiveLifecycle(): Promise<ArchiveLifecycleEvidence>;
  inspectRoute53Landing(): Promise<Route53LandingEvidence>;
}

interface ClientConfiguration {
  readonly productBaseUrl: string;
  readonly controlBaseUrl: string;
  readonly controlBearer?: string;
  readonly timeoutMs: number;
}

interface ExchangeInput {
  readonly method: 'DELETE' | 'POST';
  readonly path: string;
  readonly body?: unknown;
}

interface ExchangeOutput {
  readonly response: Response;
  readonly body: string;
}

const requireEnvironment = (environment: Readonly<Record<string, string | undefined>>, name: string): string => {
  const value = environment[name];
  if (value === undefined || value.trim().length === 0) {
    throw new MercurySitClientError('configuration', `Missing required SIT environment: ${name}`);
  }
  return value.trim();
};

const parseRootUrl = (value: string, label: string, protocols: readonly string[]): string => {
  let url: URL;
  try {
    url = new URL(value);
  } catch (error) {
    throw new MercurySitClientError('configuration', `${label} must be an absolute URL`, { cause: error });
  }
  if (!protocols.includes(url.protocol)) {
    throw new MercurySitClientError(
      'configuration',
      `${label} must use ${protocols.map(protocol => protocol.replace(':', '')).join(' or ')}`,
    );
  }
  if (
    url.username.length > 0 ||
    url.password.length > 0 ||
    url.search.length > 0 ||
    url.hash.length > 0 ||
    (url.pathname !== '' && url.pathname !== '/')
  ) {
    throw new MercurySitClientError(
      'configuration',
      `${label} must be an origin URL without credentials, path, query, or fragment`,
    );
  }
  return url.origin;
};

const parseTimeout = (value: string | undefined): number => {
  if (value === undefined) {
    return DEFAULT_TIMEOUT_MS;
  }
  if (!/^\d+$/.test(value)) {
    throw new MercurySitClientError('configuration', 'MERCURY_SIT_TIMEOUT_MS must be an integer');
  }
  const timeoutMs = Number(value);
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > MAX_TIMEOUT_MS) {
    throw new MercurySitClientError('configuration', `MERCURY_SIT_TIMEOUT_MS must be between 1 and ${MAX_TIMEOUT_MS}`);
  }
  return timeoutMs;
};

const parseBearer = (value: string | undefined): string | undefined => {
  if (value === undefined) {
    return undefined;
  }
  if (value.length === 0 || /\s/.test(value)) {
    throw new MercurySitClientError(
      'configuration',
      'MERCURY_SIT_CONTROL_BEARER must be a non-empty token without whitespace',
    );
  }
  return value;
};

const assertProviderFixtures = (actual: readonly ProviderName[]): void => {
  if (actual.length !== providerNames.length || providerNames.some((provider, index) => actual[index] !== provider)) {
    throw new MercurySitClientError(
      'configuration',
      `requiredProviderFixtures must equal the exact ordered v1 list: ${providerNames.join(', ')}`,
    );
  }
};

const parseConfiguration = (input: MercuryTestStackFactoryInput): ClientConfiguration => {
  assertProviderFixtures(input.requiredProviderFixtures);
  const productBaseUrl = parseRootUrl(
    requireEnvironment(input.environment, 'MERCURY_SIT_BASE_URL'),
    'MERCURY_SIT_BASE_URL',
    ['https:'],
  );
  const controlBaseUrl = parseRootUrl(
    requireEnvironment(input.environment, 'MERCURY_SIT_CONTROL_URL'),
    'MERCURY_SIT_CONTROL_URL',
    ['http:', 'https:'],
  );
  return {
    productBaseUrl,
    controlBaseUrl,
    controlBearer: parseBearer(input.environment.MERCURY_SIT_CONTROL_BEARER),
    timeoutMs: parseTimeout(input.environment.MERCURY_SIT_TIMEOUT_MS),
  };
};

const validationMessage = (error: z.ZodError): string =>
  error.issues
    .slice(0, 8)
    .map(issue => `${issue.path.length === 0 ? '<root>' : issue.path.join('.')}: ${issue.message}`)
    .join('; ');

class RemoteMercuryTestStack implements MercuryTestStack {
  private sessionId?: string;
  private closed = false;
  private closePromise?: Promise<void>;

  constructor(private readonly configuration: ClientConfiguration) {}

  async initialize(): Promise<void> {
    const evidence = await this.requestJson(
      {
        method: 'POST',
        path: '/v1/sessions',
        body: {
          productBaseUrl: this.configuration.productBaseUrl,
          providerFixtures: providerNames,
        },
      },
      sessionEvidenceSchema,
      'initialize',
    );
    this.sessionId = evidence.sessionId;
  }

  close(): Promise<void> {
    if (this.closePromise !== undefined) {
      return this.closePromise;
    }
    this.closed = true;
    const sessionId = this.sessionId;
    this.closePromise =
      sessionId === undefined
        ? Promise.resolve()
        : this.requestEmpty(
            {
              method: 'DELETE',
              path: `/v1/sessions/${encodeURIComponent(sessionId)}`,
            },
            204,
            'cleanup',
          );
    return this.closePromise;
  }

  inspectDependencies(): Promise<DependencyEvidence> {
    return this.runScenario('dependencies', dependencyEvidenceSchema);
  }

  runProviderVerificationMatrix(): Promise<readonly ProviderVerificationEvidence[]> {
    return this.runScenario('provider-verification', providerVerificationMatrixSchema);
  }

  runAtomicAcceptance(): Promise<AtomicAcceptanceEvidence> {
    return this.runScenario('atomic-acceptance', atomicAcceptanceEvidenceSchema);
  }

  runFanout(): Promise<FanoutEvidence> {
    return this.runScenario('fanout', fanoutEvidenceSchema);
  }

  runSignatureLifecycle(): Promise<SignatureLifecycleEvidence> {
    return this.runScenario('signature-lifecycle', signatureLifecycleEvidenceSchema);
  }

  runConsoleJourney(): Promise<ConsoleJourneyEvidence> {
    return this.runScenario('console-journey', consoleJourneyEvidenceSchema);
  }

  runAppleBackfill(): Promise<AppleBackfillEvidence> {
    return this.runScenario('apple-backfill', appleBackfillEvidenceSchema);
  }

  inspectGoogleSubscription(): Promise<GoogleSubscriptionEvidence> {
    return this.runScenario('google-subscription', googleSubscriptionEvidenceSchema);
  }

  runArchiveLifecycle(): Promise<ArchiveLifecycleEvidence> {
    return this.runScenario('archive-lifecycle', archiveLifecycleEvidenceSchema);
  }

  inspectRoute53Landing(): Promise<Route53LandingEvidence> {
    return this.runScenario('route53-landing', route53LandingEvidenceSchema);
  }

  private async runScenario<T>(name: string, schema: z.ZodType<T>): Promise<T> {
    if (this.closed) {
      throw new MercurySitClientError('closed', `Cannot run SIT scenario after close: ${name}`);
    }
    if (this.sessionId === undefined) {
      throw new MercurySitClientError('protocol', `SIT session is not initialized: ${name}`);
    }
    return this.requestJson(
      {
        method: 'POST',
        path: `/v1/sessions/${encodeURIComponent(this.sessionId)}/scenarios/${name}`,
        body: {},
      },
      schema,
      name,
    );
  }

  private async requestJson<T>(input: ExchangeInput, schema: z.ZodType<T>, operation: string): Promise<T> {
    const { response, body } = await this.exchange(input, operation);
    if (response.status !== 200) {
      throw new MercurySitClientError(
        'http',
        `SIT control operation ${operation} returned HTTP ${response.status}; expected 200`,
      );
    }
    const contentType = response.headers.get('content-type')?.split(';', 1)[0]?.trim().toLowerCase();
    if (contentType !== 'application/json') {
      throw new MercurySitClientError('protocol', `SIT control operation ${operation} must return application/json`);
    }
    let payload: unknown;
    try {
      payload = JSON.parse(body);
    } catch (error) {
      throw new MercurySitClientError('protocol', `SIT control operation ${operation} returned malformed JSON`, {
        cause: error,
      });
    }
    const parsed = schema.safeParse(payload);
    if (!parsed.success) {
      throw new MercurySitClientError(
        'protocol',
        `SIT control operation ${operation} returned incomplete evidence: ${validationMessage(parsed.error)}`,
      );
    }
    return parsed.data;
  }

  private async requestEmpty(input: ExchangeInput, expectedStatus: number, operation: string): Promise<void> {
    const { response, body } = await this.exchange(input, operation);
    if (response.status !== expectedStatus) {
      throw new MercurySitClientError(
        'http',
        `SIT control operation ${operation} returned HTTP ${response.status}; expected ${expectedStatus}`,
      );
    }
    if (body.length > 0) {
      throw new MercurySitClientError('protocol', `SIT control operation ${operation} must return an empty body`);
    }
  }

  private async exchange(input: ExchangeInput, operation: string): Promise<ExchangeOutput> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.configuration.timeoutMs);
    const headers = new Headers({
      Accept: 'application/json',
      'X-Mercury-SIT-Protocol': '1',
    });
    if (input.body !== undefined) {
      headers.set('Content-Type', 'application/json');
    }
    if (this.configuration.controlBearer !== undefined) {
      headers.set('Authorization', `Bearer ${this.configuration.controlBearer}`);
    }

    try {
      const response = await fetch(`${this.configuration.controlBaseUrl}${input.path}`, {
        method: input.method,
        headers,
        body: input.body === undefined ? undefined : JSON.stringify(input.body),
        redirect: 'error',
        signal: controller.signal,
      });
      const declaredLength = Number(response.headers.get('content-length'));
      if (Number.isFinite(declaredLength) && declaredLength > MAX_RESPONSE_BYTES) {
        throw new MercurySitClientError(
          'protocol',
          `SIT control operation ${operation} exceeded the ${MAX_RESPONSE_BYTES}-byte evidence limit`,
        );
      }
      const body = await response.text();
      if (controller.signal.aborted) {
        throw new MercurySitClientError(
          'timeout',
          `SIT control operation ${operation} exceeded ${this.configuration.timeoutMs}ms`,
        );
      }
      if (Buffer.byteLength(body) > MAX_RESPONSE_BYTES) {
        throw new MercurySitClientError(
          'protocol',
          `SIT control operation ${operation} exceeded the ${MAX_RESPONSE_BYTES}-byte evidence limit`,
        );
      }
      return { response, body };
    } catch (error) {
      if (error instanceof MercurySitClientError) {
        throw error;
      }
      if (controller.signal.aborted) {
        throw new MercurySitClientError(
          'timeout',
          `SIT control operation ${operation} exceeded ${this.configuration.timeoutMs}ms`,
          { cause: error },
        );
      }
      throw new MercurySitClientError('network', `SIT control operation ${operation} failed`, { cause: error });
    } finally {
      clearTimeout(timeout);
    }
  }
}

export const createMercuryTestStack = async (input: MercuryTestStackFactoryInput): Promise<MercuryTestStack> => {
  const stack = new RemoteMercuryTestStack(parseConfiguration(input));
  await stack.initialize();
  return stack;
};
