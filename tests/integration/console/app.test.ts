import { describe, it } from 'bun:test';
import should from 'should';
import { createConsoleApp } from '../../../src/console/app.ts';
import type {
  ConsoleActionReceipt,
  ConsoleAuthenticationResult,
  ConsoleAuthorizationScope,
  ConsoleCapability,
  ConsoleCredentials,
  ConsoleDashboardSnapshot,
  ConsoleEndpointReplayTarget,
  ConsoleEventDetail,
  ConsoleFilters,
  ConsoleIdentity,
  ConsoleLandscapeSource,
  ConsoleNativeAuthorization,
  ConsoleResult,
  ConsoleSessionRecord,
} from '../../../src/console/model.ts';
import type {
  ConsoleAuthorizationExchange,
  ConsoleClock,
  ConsoleIncidentReporter,
  ConsoleManagementAccountGateway,
  ConsoleOperations,
  ConsoleRequestSecurity,
  ConsoleSessionCryptography,
  ConsoleSessionRepository,
} from '../../../src/console/ports.ts';
import { ConsoleSessionManager } from '../../../src/console/session.ts';

const ORIGIN = 'https://mercury.example.test';
const SESSION_COOKIE = '__Host-mercury_console_session';
const LOGIN_CSRF_COOKIE = '__Host-mercury_console_login_csrf';

const identity: ConsoleIdentity = {
  accountId: 'account-1',
  accountName: 'internal/default',
  accountKind: 'default-internal',
};

const scope: ConsoleAuthorizationScope = {
  tenants: ['internal/primordial'],
  landscapes: ['serving'],
  capabilities: ['operations:read', 'events:replay', 'endpoints:replay', 'endpoints:reenable'],
};

const event: ConsoleEventDetail = {
  id: 'evt_42',
  landscape: 'serving',
  tenant: 'internal/primordial',
  provider: 'stripe',
  route: 'billing',
  endpointId: 'endpoint-1',
  endpointName: '<Billing Receiver>',
  status: 'dead-lettered',
  receivedAt: new Date('2026-07-29T00:00:00.000Z'),
  providerTimestamp: new Date('2026-07-28T23:59:59.000Z'),
  providerSequence: 'sequence-9',
  attemptCount: 12,
  lagSeconds: 7_200,
  allowedHeaders: { 'content-type': 'application/json' },
  metadata: { source: '<script>alert(1)</script>' },
  payload: '{"event":"</script><script>alert(1)</script>"}',
  payloadMediaType: 'application/json',
  deliveryAddress: 'http://receiver.internal/hooks',
  lastResponseStatus: 503,
  lastResponseBody: '<temporarily unavailable>',
};

const endpoint: ConsoleEndpointReplayTarget = {
  endpointId: 'endpoint-1',
  endpointName: 'Billing Receiver',
  tenant: 'internal/primordial',
  provider: 'stripe',
  landscape: 'serving',
  circuit: 'open',
  replayableEvents: 3,
  oldestEventAt: new Date('2026-07-28T20:00:00.000Z'),
};

const snapshot: ConsoleDashboardSnapshot = {
  generatedAt: new Date('2026-07-29T00:01:00.000Z'),
  filterOptions: {
    landscapes: [{ value: 'serving', label: 'Serving' }],
    tenants: [{ value: 'internal/primordial', label: 'Primordial' }],
    providers: [{ value: 'stripe', label: 'Stripe' }],
    endpoints: [{ value: 'endpoint-1', label: 'Billing Receiver' }],
  },
  intake: [
    {
      landscape: 'serving',
      state: 'healthy',
      eventsPerMinute: 20,
      verificationFailureRate: 0.01,
      dedupHitRate: 0.04,
      lastAcceptedAt: new Date('2026-07-29T00:00:58.000Z'),
    },
  ],
  deliveries: [
    {
      endpointId: endpoint.endpointId,
      endpointName: endpoint.endpointName,
      tenant: endpoint.tenant,
      provider: endpoint.provider,
      landscape: endpoint.landscape,
      state: 'critical',
      circuit: 'open',
      successRate: 0.72,
      retryDepth: 18,
      lagSeconds: 7_200,
      deadLetterCount: 3,
      canReenable: true,
    },
  ],
  events: [event],
  deadLetters: [
    {
      eventId: event.id,
      landscape: event.landscape,
      tenant: event.tenant,
      provider: event.provider,
      endpointId: event.endpointId,
      endpointName: event.endpointName,
      exhaustedAt: new Date('2026-07-29T00:00:20.000Z'),
      finalStatus: 503,
      attempts: 12,
    },
  ],
  routes: [
    {
      routeId: 'route-1',
      route: 'billing',
      tenant: 'internal/primordial',
      provider: 'stripe',
      landscape: 'serving',
      endpointCount: 1,
      state: 'active',
      activeGeneration: 43,
    },
  ],
  generations: [
    {
      landscape: 'serving',
      desiredGeneration: 44,
      activeGeneration: 43,
      state: 'stale',
    },
  ],
  archives: [
    {
      landscape: 'serving',
      state: 'blocked',
      pendingStreams: 1,
      pendingBytes: 2_048,
      deletionBlocked: true,
    },
  ],
  quotas: [
    {
      tenant: 'internal/primordial',
      state: 'approaching',
      used: 8_000,
      limit: 10_000,
      window: '1 minute',
      resetsAt: new Date('2026-07-29T00:02:00.000Z'),
    },
  ],
  previewVisibility: {
    state: 'withheld-d11',
    detail: 'Preview callback delivery visibility is withheld pending D11.',
    affectedLandscapes: ['castform'],
  },
  sourceFailures: [],
};

class MutableClock implements ConsoleClock {
  value = new Date('2026-07-29T00:00:00.000Z');

  now(): Date {
    return new Date(this.value);
  }
}

class MemorySessionRepository implements ConsoleSessionRepository {
  readonly records = new Map<string, ConsoleSessionRecord>();

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
    if (!this.records.has(currentTokenHash)) return false;
    this.records.delete(currentTokenHash);
    this.records.set(replacement.tokenHash, replacement);
    return true;
  }

  async delete(tokenHash: string): Promise<void> {
    this.records.delete(tokenHash);
  }
}

class DeterministicSessionCryptography implements ConsoleSessionCryptography {
  counter = 0;

  randomToken(byteLength: number): string {
    this.counter += 1;
    return `session-${byteLength}-${String(this.counter).padStart(32, '0')}`;
  }

  async hashToken(token: string): Promise<string> {
    return `hash:${token}`;
  }

  async deriveCsrfToken(token: string): Promise<string> {
    return `csrf:${token}`;
  }
}

class DeterministicRequestSecurity implements ConsoleRequestSecurity {
  counter = 0;

  issueToken(byteLength: number): string {
    this.counter += 1;
    return `request-${byteLength}-${String(this.counter).padStart(32, '0')}`;
  }

  equal(left: string, right: string): boolean {
    return left === right;
  }
}

class FakeManagementGateway implements ConsoleManagementAccountGateway {
  readonly calls: ConsoleCredentials[] = [];
  scope: ConsoleAuthorizationScope = scope;
  result: ConsoleAuthenticationResult | undefined;

  async authenticate(credentials: ConsoleCredentials): Promise<ConsoleAuthenticationResult> {
    this.calls.push(credentials);
    return this.result ?? { kind: 'authenticated', identity, scope: this.scope };
  }

  async landscapeSources(): Promise<ConsoleResult<readonly ConsoleLandscapeSource[]>> {
    return { ok: true, value: [] };
  }
}

interface AuthorizationCall {
  readonly sessionId: string;
  readonly requiredCapabilities: readonly ConsoleCapability[];
  readonly optionalCapabilities: readonly ConsoleCapability[];
}

class FakeAuthorizationExchange implements ConsoleAuthorizationExchange {
  readonly calls: AuthorizationCall[] = [];
  availableCapabilities: readonly ConsoleCapability[] = [
    'operations:read',
    'events:replay',
    'endpoints:replay',
    'endpoints:reenable',
  ];
  now = new Date('2026-07-29T00:00:00.000Z');

  async exchange(request: {
    readonly sessionId: string;
    readonly identity: ConsoleIdentity;
    readonly scope: ConsoleAuthorizationScope;
    readonly requiredCapabilities: readonly ConsoleCapability[];
    readonly optionalCapabilities: readonly ConsoleCapability[];
  }): Promise<ConsoleResult<ConsoleNativeAuthorization>> {
    this.calls.push({
      sessionId: request.sessionId,
      requiredCapabilities: request.requiredCapabilities,
      optionalCapabilities: request.optionalCapabilities,
    });
    if (
      !request.requiredCapabilities.every(
        capability =>
          this.availableCapabilities.includes(capability) && request.scope.capabilities.includes(capability),
      )
    ) {
      return {
        ok: false,
        error: {
          kind: 'forbidden',
          title: 'Capability unavailable',
          detail: 'This account cannot perform the requested operation.',
        },
      };
    }
    const capabilities = [
      ...request.requiredCapabilities,
      ...request.optionalCapabilities.filter(
        capability =>
          this.availableCapabilities.includes(capability) && request.scope.capabilities.includes(capability),
      ),
    ].filter((capability, index, values) => values.indexOf(capability) === index);
    return {
      ok: true,
      value: {
        scheme: 'Bearer',
        token: 'native-bearer-token-never-rendered',
        expiresAt: new Date(this.now.getTime() + 60_000),
        accountId: request.identity.accountId,
        sessionId: request.sessionId,
        scope: {
          tenants: request.scope.tenants,
          landscapes: request.scope.landscapes,
          capabilities,
        },
      },
    };
  }
}

class FakeOperations implements ConsoleOperations {
  readonly authorizations: ConsoleNativeAuthorization[] = [];
  readonly dashboardFilters: ConsoleFilters[] = [];
  readonly replayEventCalls: Parameters<ConsoleOperations['replayEvent']>[1][] = [];
  readonly replayEndpointCalls: Parameters<ConsoleOperations['replayEndpoint']>[1][] = [];
  readonly reenableEndpointCalls: Parameters<ConsoleOperations['reenableEndpoint']>[1][] = [];
  dashboardError: Error | undefined;

  async dashboard(
    authorization: ConsoleNativeAuthorization,
    filters: ConsoleFilters,
  ): Promise<ConsoleResult<ConsoleDashboardSnapshot>> {
    if (this.dashboardError !== undefined) throw this.dashboardError;
    this.authorizations.push(authorization);
    this.dashboardFilters.push(filters);
    return { ok: true, value: snapshot };
  }

  async event(
    authorization: ConsoleNativeAuthorization,
    _landscape: string,
    _eventId: string,
  ): Promise<ConsoleResult<ConsoleEventDetail>> {
    this.authorizations.push(authorization);
    return { ok: true, value: event };
  }

  async endpoint(
    authorization: ConsoleNativeAuthorization,
    _landscape: string,
    _endpointId: string,
  ): Promise<ConsoleResult<ConsoleEndpointReplayTarget>> {
    this.authorizations.push(authorization);
    return { ok: true, value: endpoint };
  }

  async replayEvent(
    authorization: ConsoleNativeAuthorization,
    input: Parameters<ConsoleOperations['replayEvent']>[1],
  ): Promise<ConsoleResult<ConsoleActionReceipt>> {
    this.authorizations.push(authorization);
    this.replayEventCalls.push(input);
    return {
      ok: true,
      value: {
        actionId: 'action-event-1',
        title: 'Replay accepted',
        detail: 'The retained event was queued in serving.',
        acceptedAt: new Date('2026-07-29T00:01:00.000Z'),
        landscape: 'serving',
        affectedCount: 1,
      },
    };
  }

  async replayEndpoint(
    authorization: ConsoleNativeAuthorization,
    input: Parameters<ConsoleOperations['replayEndpoint']>[1],
  ): Promise<ConsoleResult<ConsoleActionReceipt>> {
    this.authorizations.push(authorization);
    this.replayEndpointCalls.push(input);
    return {
      ok: true,
      value: {
        actionId: 'action-endpoint-1',
        title: 'Endpoint replay accepted',
        detail: 'Three retained obligations were queued.',
        acceptedAt: new Date('2026-07-29T00:01:00.000Z'),
        landscape: 'serving',
        affectedCount: 3,
      },
    };
  }

  async reenableEndpoint(
    authorization: ConsoleNativeAuthorization,
    input: Parameters<ConsoleOperations['reenableEndpoint']>[1],
  ): Promise<ConsoleResult<ConsoleActionReceipt>> {
    this.authorizations.push(authorization);
    this.reenableEndpointCalls.push(input);
    return {
      ok: true,
      value: {
        actionId: 'action-circuit-1',
        title: 'Circuit re-enabled',
        detail: 'Delivery retries may resume.',
        acceptedAt: new Date('2026-07-29T00:01:00.000Z'),
        landscape: 'serving',
        affectedCount: 1,
      },
    };
  }
}

class FakeIncidentReporter implements ConsoleIncidentReporter {
  readonly calls: Parameters<ConsoleIncidentReporter['report']>[0][] = [];

  async report(input: Parameters<ConsoleIncidentReporter['report']>[0]): Promise<void> {
    this.calls.push(input);
  }
}

const makeHarness = () => {
  const clock = new MutableClock();
  const repository = new MemorySessionRepository();
  const managementGateway = new FakeManagementGateway();
  const authorization = new FakeAuthorizationExchange();
  const operations = new FakeOperations();
  const requestSecurity = new DeterministicRequestSecurity();
  const incidentReporter = new FakeIncidentReporter();
  const sessions = new ConsoleSessionManager(repository, new DeterministicSessionCryptography(), {
    idleTtlSeconds: 900,
    absoluteTtlSeconds: 28_800,
    rotationIntervalSeconds: 1_800,
  });
  const app = createConsoleApp(
    {
      clock,
      sessions,
      managementGateway,
      authorization,
      operations,
      requestSecurity,
      incidentReporter,
    },
    { origin: ORIGIN },
  );
  return { app, managementGateway, authorization, operations, repository, incidentReporter };
};

type Harness = ReturnType<typeof makeHarness>;
type AppResponse = Awaited<ReturnType<Harness['app']['request']>>;

const cookieHeader = (response: AppResponse): string => {
  const headers = response.headers as typeof response.headers & {
    getSetCookie?: () => string[];
  };
  return headers.getSetCookie?.().join('\n') ?? response.headers.get('set-cookie') ?? '';
};

const cookieValue = (response: AppResponse, name: string): string => {
  const match = cookieHeader(response).match(new RegExp(`${name}=([^;\\n,]*)`));
  if (match?.[1] === undefined) throw new Error(`Cookie ${name} was not set`);
  return match[1];
};

const csrfValue = async (response: AppResponse): Promise<string> => {
  const match = (await response.text()).match(/name="csrf" value="([^"]+)"/);
  if (match?.[1] === undefined) throw new Error('CSRF field was not rendered');
  return match[1];
};

const post = (
  harness: Harness,
  path: string,
  body: URLSearchParams | string,
  cookie?: string,
  origin = ORIGIN,
): Promise<AppResponse> =>
  Promise.resolve(
    harness.app.request(`${ORIGIN}${path}`, {
      method: 'POST',
      headers: {
        'content-type': 'application/x-www-form-urlencoded',
        origin,
        ...(cookie === undefined ? {} : { cookie }),
      },
      body: typeof body === 'string' ? body : body.toString(),
    }),
  );

const chunkedPost = (
  harness: Harness,
  path: string,
  chunks: readonly string[],
  cookie?: string,
): { readonly response: Promise<AppResponse>; readonly wasCancelled: () => boolean } => {
  const encodedChunks = chunks.map(chunk => new TextEncoder().encode(chunk));
  let nextChunk = 0;
  let cancelled = false;
  const body = new ReadableStream<Uint8Array>({
    pull(controller) {
      const chunk = encodedChunks[nextChunk];
      nextChunk += 1;
      if (chunk === undefined) {
        controller.close();
        return;
      }
      controller.enqueue(chunk);
    },
    cancel() {
      cancelled = true;
    },
  });
  const init: RequestInit & { readonly duplex: 'half' } = {
    method: 'POST',
    headers: {
      'content-type': 'application/x-www-form-urlencoded',
      origin: ORIGIN,
      ...(cookie === undefined ? {} : { cookie }),
    },
    body,
    duplex: 'half',
  };
  return {
    response: Promise.resolve(harness.app.fetch(new Request(`${ORIGIN}${path}`, init))),
    wasCancelled: () => cancelled,
  };
};

const login = async (harness: Harness): Promise<{ readonly response: AppResponse; readonly sessionCookie: string }> => {
  const loginPage = await harness.app.request(`${ORIGIN}/console/login`);
  const loginCsrf = await csrfValue(loginPage);
  const preAuthCookie = `${LOGIN_CSRF_COOKIE}=${cookieValue(loginPage, LOGIN_CSRF_COOKIE)}`;
  const response = await post(
    harness,
    '/console/login',
    new URLSearchParams({
      csrf: loginCsrf,
      accountName: 'internal/default',
      bearerCredential: 'native-management-bearer-secret',
    }),
    preAuthCookie,
  );
  return {
    response,
    sessionCookie: `${SESSION_COOKIE}=${cookieValue(response, SESSION_COOKIE)}`,
  };
};

describe('Mercury console HTTP surface', () => {
  it('serves login with hardened cookies, CSP nonces, and cache isolation', async () => {
    // Arrange
    const harness = makeHarness();

    // Act
    const response = await harness.app.request(`${ORIGIN}/console/login`);
    const document = await response.text();
    const cookies = cookieHeader(response);

    // Assert
    should(response.status).equal(200);
    should(cookies).containEql(`${LOGIN_CSRF_COOKIE}=`);
    should(cookies).containEql('HttpOnly');
    should(cookies).containEql('Secure');
    should(cookies).containEql('SameSite=Strict');
    should(cookies).containEql('Path=/');
    should(response.headers.get('cache-control')).containEql('no-store');
    should(response.headers.get('strict-transport-security')).containEql('max-age=');
    should(response.headers.get('content-security-policy')).containEql("default-src 'none'");
    should(response.headers.get('content-security-policy')).not.containEql("'unsafe-inline'");
    should(document).match(/<style nonce="request-18-[0-9]+">/);
    should(document).containEql('internal/default');
    should(document).containEql('Native bearer credential');
  });

  it('rejects cross-site and duplicate-CSRF login submissions before authentication', async () => {
    // Arrange
    const harness = makeHarness();
    const page = await harness.app.request(`${ORIGIN}/console/login`);
    const csrf = await csrfValue(page);
    const cookie = `${LOGIN_CSRF_COOKIE}=${cookieValue(page, LOGIN_CSRF_COOKIE)}`;
    const fields = new URLSearchParams({
      csrf,
      accountName: 'internal/default',
      bearerCredential: 'native-management-bearer-secret',
    });

    // Act
    const crossSite = await post(harness, '/console/login', fields, cookie, 'https://evil.test');
    const duplicated = await post(
      harness,
      '/console/login',
      `csrf=${encodeURIComponent(csrf)}&csrf=${encodeURIComponent(
        csrf,
      )}&accountName=internal%2Fdefault&bearerCredential=native-management-bearer-secret`,
      cookie,
    );

    // Assert
    should(crossSite.status).equal(403);
    should(duplicated.status).equal(403);
    should(harness.managementGateway.calls.length).equal(0);
  });

  it('cancels an oversized chunked login form with 413 before authentication or session creation', async () => {
    // Arrange
    const harness = makeHarness();
    const page = await harness.app.request(`${ORIGIN}/console/login`);
    const csrf = await csrfValue(page);
    const cookie = `${LOGIN_CSRF_COOKIE}=${cookieValue(page, LOGIN_CSRF_COOKIE)}`;
    const request = chunkedPost(
      harness,
      '/console/login',
      [
        `csrf=${encodeURIComponent(csrf)}&accountName=internal%2Fdefault&bearerCredential=native-management-bearer-secret&padding=${'a'.repeat(4_096)}`,
        'b'.repeat(4_096),
        'c'.repeat(1_024),
      ],
      cookie,
    );

    // Act
    const response = await request.response;
    const document = await response.text();

    // Assert
    should(response.status).equal(413);
    should(request.wasCancelled()).equal(true);
    should(document).containEql('Sign-in request rejected');
    should(document).not.containEql('native-management-bearer-secret');
    should(harness.managementGateway.calls).have.length(0);
    should(harness.repository.records.size).equal(0);
  });

  it('accepts a bounded chunked login form without materializing through Request.text', async () => {
    // Arrange
    const harness = makeHarness();
    const page = await harness.app.request(`${ORIGIN}/console/login`);
    const csrf = await csrfValue(page);
    const cookie = `${LOGIN_CSRF_COOKIE}=${cookieValue(page, LOGIN_CSRF_COOKIE)}`;
    const request = chunkedPost(
      harness,
      '/console/login',
      [
        `csrf=${encodeURIComponent(csrf)}`,
        '&accountName=internal%2Fdefault',
        '&bearerCredential=native-management-bearer-secret',
      ],
      cookie,
    );

    // Act
    const response = await request.response;

    // Assert
    should(response.status).equal(303);
    should(request.wasCancelled()).equal(false);
    should(harness.managementGateway.calls).have.length(1);
    should(harness.repository.records.size).equal(1);
  });

  it('rotates from pre-auth state into a secure opaque console session', async () => {
    // Arrange
    const harness = makeHarness();

    // Act
    const authenticated = await login(harness);
    const cookies = cookieHeader(authenticated.response);

    // Assert
    should(authenticated.response.status).equal(303);
    should(authenticated.response.headers.get('location')).equal('/console');
    should(cookies).containEql(`${SESSION_COOKIE}=session-32-`);
    should(cookies).containEql('HttpOnly');
    should(cookies).containEql('Secure');
    should(cookies).containEql('SameSite=Strict');
    should(cookies).containEql(`${LOGIN_CSRF_COOKIE}=;`);
    should(harness.managementGateway.calls[0]?.accountName).equal('internal/default');
    should(harness.managementGateway.calls[0]?.bearerCredential).equal('native-management-bearer-secret');
    should(harness.repository.records.size).equal(1);
    should(JSON.stringify([...harness.repository.records.values()])).not.containEql('native-management-bearer-secret');
  });

  it('renders rate limiting as a generic authentication rejection without echoing the bearer', async () => {
    // Arrange
    const harness = makeHarness();
    harness.managementGateway.result = { kind: 'rate-limited', retryAfterSeconds: 19 };
    const page = await harness.app.request(`${ORIGIN}/console/login`);
    const csrf = await csrfValue(page);
    const cookie = `${LOGIN_CSRF_COOKIE}=${cookieValue(page, LOGIN_CSRF_COOKIE)}`;

    // Act
    const response = await post(
      harness,
      '/console/login',
      new URLSearchParams({
        csrf,
        accountName: 'internal/default',
        bearerCredential: 'native-management-bearer-secret',
      }),
      cookie,
    );
    const document = await response.text();

    // Assert
    should(response.status).equal(429);
    should(response.headers.get('retry-after')).equal('19');
    should(document).containEql('Unable to authenticate');
    should(document).containEql('Too many attempts');
    should(document).not.containEql('native-management-bearer-secret');
    should(harness.repository.records.size).equal(0);
  });

  it('exchanges the console session server-side and never renders native bearer authorization', async () => {
    // Arrange
    const harness = makeHarness();
    const authenticated = await login(harness);

    // Act
    const response = await harness.app.request(`${ORIGIN}/console?status=dead-lettered`, {
      headers: { cookie: authenticated.sessionCookie },
    });
    const document = await response.text();

    // Assert
    should(response.status).equal(200);
    should(harness.authorization.calls[0]?.requiredCapabilities).deepEqual(['operations:read']);
    should(harness.authorization.calls[0]?.optionalCapabilities).deepEqual([
      'events:replay',
      'endpoints:replay',
      'endpoints:reenable',
    ]);
    should(harness.operations.authorizations[0]?.scheme).equal('Bearer');
    should(harness.operations.authorizations[0]?.token).equal('native-bearer-token-never-rendered');
    should(document).not.containEql('native-bearer-token-never-rendered');
    should(document).containEql('data-preview-visibility="withheld-d11"');
    should(harness.operations.dashboardFilters[0]?.status).equal('dead-lettered');
  });

  it('blocks tenant filters outside the bearer scope before querying fan-in services', async () => {
    // Arrange
    const harness = makeHarness();
    harness.managementGateway.scope = { ...scope, tenants: ['external/acme'] };
    const authenticated = await login(harness);

    // Act
    const response = await harness.app.request(`${ORIGIN}/console?tenant=external%2Fother&status=all`, {
      headers: { cookie: authenticated.sessionCookie },
    });
    const document = await response.text();

    // Assert
    should(response.status).equal(403);
    should(document).containEql('Filter is outside account scope');
    should(harness.operations.dashboardFilters.length).equal(0);
  });

  it('renders event payload and metadata as escaped retained content', async () => {
    // Arrange
    const harness = makeHarness();
    const authenticated = await login(harness);

    // Act
    const response = await harness.app.request(`${ORIGIN}/console/events/serving/evt_42`, {
      headers: { cookie: authenticated.sessionCookie },
    });
    const document = await response.text();

    // Assert
    should(response.status).equal(200);
    should(document).containEql('&lt;script&gt;alert(1)&lt;/script&gt;');
    should(document).not.containEql('<script>alert(1)</script>');
    should(document).containEql('sequence-9');
  });

  it('requires origin, session CSRF, exact phrase, and audit reason for event replay', async () => {
    // Arrange
    const harness = makeHarness();
    const authenticated = await login(harness);
    const confirmation = await harness.app.request(
      `${ORIGIN}/console/events/serving/evt_42/replay?endpoint=endpoint-1`,
      { headers: { cookie: authenticated.sessionCookie } },
    );
    const csrf = await csrfValue(confirmation);
    const validFields = new URLSearchParams({
      csrf,
      confirmation: 'REPLAY EVENT',
      reason: 'Receiver recovered after incident.',
    });

    // Act
    const crossSite = await post(
      harness,
      '/console/events/serving/evt_42/replay?endpoint=endpoint-1',
      validFields,
      authenticated.sessionCookie,
      'https://evil.test',
    );
    const wrongPhrase = await post(
      harness,
      '/console/events/serving/evt_42/replay?endpoint=endpoint-1',
      new URLSearchParams({
        csrf,
        confirmation: 'REPLAY',
        reason: 'Receiver recovered after incident.',
      }),
      authenticated.sessionCookie,
    );
    const accepted = await post(
      harness,
      '/console/events/serving/evt_42/replay?endpoint=endpoint-1',
      validFields,
      authenticated.sessionCookie,
    );
    const document = await accepted.text();

    // Assert
    should(crossSite.status).equal(403);
    should(wrongPhrase.status).equal(400);
    should(accepted.status).equal(200);
    should(document).containEql('Replay accepted');
    should(harness.operations.replayEventCalls.length).equal(1);
    should(harness.operations.replayEventCalls[0]?.endpointId).equal('endpoint-1');
    should(harness.operations.replayEventCalls[0]?.audit.reason).equal('Receiver recovered after incident.');
    should(harness.operations.replayEventCalls[0]?.audit.sessionId.length).be.greaterThan(20);
    should(harness.authorization.calls.at(-1)?.requiredCapabilities).deepEqual(['operations:read', 'events:replay']);
  });

  it('cancels oversized chunked forms on every authenticated mutation before logout, action, or audit', async () => {
    // Arrange
    const harness = makeHarness();
    const authenticated = await login(harness);
    const dashboard = await harness.app.request(`${ORIGIN}/console`, {
      headers: { cookie: authenticated.sessionCookie },
    });
    const csrf = await csrfValue(dashboard);
    const prefix = `csrf=${encodeURIComponent(csrf)}&confirmation=REPLAY%20EVENT&reason=Reviewed&padding=`;
    const paths = [
      '/console/logout',
      '/console/events/serving/evt_42/replay?endpoint=endpoint-1',
      '/console/endpoints/serving/endpoint-1/replay',
      '/console/endpoints/serving/endpoint-1/reenable',
    ] as const;
    // Act
    const requests: ReturnType<typeof chunkedPost>[] = [];
    const responses: AppResponse[] = [];
    for (const path of paths) {
      const request = chunkedPost(
        harness,
        path,
        [`${prefix}${'a'.repeat(4_096)}`, 'b'.repeat(4_096), 'c'.repeat(1_024)],
        authenticated.sessionCookie,
      );
      requests.push(request);
      responses.push(await request.response);
    }

    // Assert
    should(responses.map(response => response.status)).deepEqual([413, 413, 413, 413]);
    should(requests.every(request => request.wasCancelled())).equal(true);
    should(harness.repository.records.size).equal(1);
    should(harness.operations.replayEventCalls).have.length(0);
    should(harness.operations.replayEndpointCalls).have.length(0);
    should(harness.operations.reenableEndpointCalls).have.length(0);
  });

  it('executes endpoint replay and manual circuit re-enable through distinct service actions', async () => {
    // Arrange
    const harness = makeHarness();
    const authenticated = await login(harness);
    const replayPage = await harness.app.request(`${ORIGIN}/console/endpoints/serving/endpoint-1/replay`, {
      headers: { cookie: authenticated.sessionCookie },
    });
    const replayCsrf = await csrfValue(replayPage);
    const reenablePage = await harness.app.request(`${ORIGIN}/console/endpoints/serving/endpoint-1/reenable`, {
      headers: { cookie: authenticated.sessionCookie },
    });
    const reenableCsrf = await csrfValue(reenablePage);

    // Act
    const replay = await post(
      harness,
      '/console/endpoints/serving/endpoint-1/replay',
      new URLSearchParams({
        csrf: replayCsrf,
        confirmation: 'REPLAY ENDPOINT',
        reason: 'DLQ reviewed and receiver repaired.',
      }),
      authenticated.sessionCookie,
    );
    const reenable = await post(
      harness,
      '/console/endpoints/serving/endpoint-1/reenable',
      new URLSearchParams({
        csrf: reenableCsrf,
        confirmation: 'REENABLE',
        reason: 'Probe succeeded after receiver repair.',
      }),
      authenticated.sessionCookie,
    );

    // Assert
    should(replay.status).equal(200);
    should(reenable.status).equal(200);
    should(harness.operations.replayEndpointCalls[0]?.endpointId).equal('endpoint-1');
    should(harness.operations.replayEndpointCalls[0]?.landscape).equal('serving');
    should(harness.operations.reenableEndpointCalls[0]?.endpointId).equal('endpoint-1');
    should(harness.operations.reenableEndpointCalls[0]?.landscape).equal('serving');
    should(harness.operations.replayEndpointCalls[0]?.audit.requestId).not.equal(
      harness.operations.reenableEndpointCalls[0]?.audit.requestId,
    );
  });

  it('contains unexpected adapter failures behind a request reference', async () => {
    // Arrange
    const harness = makeHarness();
    const authenticated = await login(harness);
    harness.operations.dashboardError = new Error('sensitive adapter detail: native-bearer-token-never-rendered');

    // Act
    const response = await harness.app.request(`${ORIGIN}/console`, {
      headers: { cookie: authenticated.sessionCookie },
    });
    const document = await response.text();

    // Assert
    should(response.status).equal(500);
    should(response.headers.get('x-request-id')).match(/^request-16-/);
    should(response.headers.get('content-security-policy')).containEql("default-src 'none'");
    should(document).containEql('Console operation interrupted');
    should(document).containEql('Request reference:');
    should(document).not.containEql('sensitive adapter detail');
    should(document).not.containEql('native-bearer-token-never-rendered');
    should(harness.incidentReporter.calls.length).equal(1);
    should(harness.incidentReporter.calls[0]?.method).equal('GET');
    should(harness.incidentReporter.calls[0]?.path).equal('/console');
  });

  it('returns a hardened product response for unknown console routes', async () => {
    // Arrange
    const harness = makeHarness();

    // Act
    const response = await harness.app.request(`${ORIGIN}/console/not-a-route`);
    const document = await response.text();

    // Assert
    should(response.status).equal(404);
    should(response.headers.get('cache-control')).containEql('no-store');
    should(response.headers.get('content-security-policy')).containEql("frame-ancestors 'none'");
    should(document).containEql('Console route not found');
  });

  it('revokes logout state and clears the session cookie', async () => {
    // Arrange
    const harness = makeHarness();
    const authenticated = await login(harness);
    const dashboard = await harness.app.request(`${ORIGIN}/console`, {
      headers: { cookie: authenticated.sessionCookie },
    });
    const csrf = await csrfValue(dashboard);

    // Act
    const logout = await post(harness, '/console/logout', new URLSearchParams({ csrf }), authenticated.sessionCookie);
    const afterLogout = await harness.app.request(`${ORIGIN}/console`, {
      headers: { cookie: authenticated.sessionCookie },
    });

    // Assert
    should(logout.status).equal(303);
    should(logout.headers.get('location')).equal('/console/login');
    should(cookieHeader(logout)).containEql(`${SESSION_COOKIE}=;`);
    should(harness.repository.records.size).equal(0);
    should(afterLogout.status).equal(303);
    should(afterLogout.headers.get('location')).equal('/console/login');
  });
});
