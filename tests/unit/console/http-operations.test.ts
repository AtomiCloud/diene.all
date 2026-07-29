import { describe, it } from 'bun:test';
import should from 'should';
import { HttpConsoleOperations } from '../../../src/console/http-operations.ts';
import type {
  ConsoleActionAuditRequest,
  ConsoleAuthenticationResult,
  ConsoleCredentials,
  ConsoleLandscapeSource,
  ConsoleNativeAuthorization,
  ConsoleResult,
} from '../../../src/console/model.ts';
import type {
  ConsoleActionAuditor,
  ConsoleClock,
  ConsoleManagementAccountGateway,
} from '../../../src/console/ports.ts';

const TOKEN = 'signed-console-native-bearer-that-must-never-render';

class FixedClock implements ConsoleClock {
  now(): Date {
    return new Date('2026-07-29T01:00:00.000Z');
  }
}

class FakeGateway implements ConsoleManagementAccountGateway {
  constructor(
    readonly sources: readonly ConsoleLandscapeSource[] = [
      {
        trustKind: 'account-owned',
        accountId: 'account-1',
        landscape: 'castform',
        queryUrl: 'https://castform.example.test/query',
        queryOrigin: 'https://castform.example.test',
        replayUrl: 'https://castform.example.test/actions',
        replayOrigin: 'https://castform.example.test',
        enabled: true,
      },
      {
        trustKind: 'account-owned',
        accountId: 'account-1',
        landscape: 'serving',
        queryUrl: 'https://serving.example.test/query',
        queryOrigin: 'https://serving.example.test',
        replayUrl: 'https://serving.example.test/actions',
        replayOrigin: 'https://serving.example.test',
        enabled: true,
      },
    ],
  ) {}

  async authenticate(_credentials: ConsoleCredentials): Promise<ConsoleAuthenticationResult> {
    return { kind: 'rejected' };
  }

  async landscapeSources(): Promise<ConsoleResult<readonly ConsoleLandscapeSource[]>> {
    return { ok: true, value: this.sources };
  }
}

const authorization: ConsoleNativeAuthorization = {
  scheme: 'Bearer',
  token: TOKEN,
  expiresAt: new Date('2026-07-29T01:01:00.000Z'),
  accountId: 'account-1',
  sessionId: 'session-12345678',
  scope: {
    tenants: ['tenant-1'],
    landscapes: ['castform', 'serving'],
    capabilities: ['operations:read', 'events:replay', 'endpoints:replay', 'endpoints:reenable'],
  },
};

const acceptingAuditor: ConsoleActionAuditor = {
  async accept(_request: ConsoleActionAuditRequest): Promise<ConsoleResult<void>> {
    return { ok: true, value: undefined };
  },
};

const json = (value: unknown, status = 200): Response =>
  new Response(JSON.stringify(value), {
    status,
    headers: { 'content-type': status >= 400 ? 'application/problem+json' : 'application/json' },
  });

const health = (landscape: string) => ({
  landscape,
  status: 'healthy',
  checkedAtMs: Date.parse('2026-07-29T00:59:59.000Z'),
  activeGeneration: 12,
  compiledAtMs: Date.parse('2026-07-29T00:58:00.000Z'),
  sourceRevision: 'revision-12',
  supervisor: 'running',
});

const eventSummary = (landscape = 'serving') => ({
  id: 'evt-1',
  tenantId: 'tenant-1',
  routeId: 'billing',
  provider: 'stripe',
  landscape,
  receivedAtMs: Date.parse('2026-07-29T00:55:00.000Z'),
  providerEventId: 'provider-evt-1',
  providerTimestampMs: Date.parse('2026-07-29T00:54:59.000Z'),
  providerSequence: 'sequence-1',
  status: 'dead-letter',
  endpointIds: ['endpoint-1'],
  attemptCount: 3,
});

const eventList = (landscape: string, items: readonly unknown[]) => ({
  landscape,
  tenantId: 'tenant-1',
  items,
});

const deadLetterList = (landscape: string, items: readonly unknown[] = []) => ({
  landscape,
  tenantId: 'tenant-1',
  items,
});

const detail = (sensitiveValue = 'safe') => ({
  event: eventSummary(),
  headers: {
    authorization: sensitiveValue,
    'content-type': 'application/json',
    'x-request-id': 'request-1',
  },
  verificationMetadata: { verifier: sensitiveValue },
  rawBodyBase64: Buffer.from(`payload:${sensitiveValue}`).toString('base64'),
  jobs: [
    {
      id: 'job-1',
      eventId: 'evt-1',
      endpointId: 'endpoint-1',
      address: `https://receiver.example.test/${sensitiveValue}`,
      addressKind: 'external',
      createdAtMs: Date.parse('2026-07-29T00:55:00.000Z'),
      dueAtMs: Date.parse('2026-07-29T00:59:00.000Z'),
      retryWindowMs: 72 * 60 * 60 * 1_000,
      status: 'dead-letter',
      attempts: [
        {
          number: 1,
          attemptedAtMs: Date.parse('2026-07-29T00:59:00.000Z'),
          address: 'https://receiver.example.test/hook',
          transportError: sensitiveValue,
          replay: false,
        },
      ],
      misrouteRefreshes: 0,
      replayCount: 0,
    },
  ],
});

const asFetch = (implementation: (url: URL, init: RequestInit | undefined) => Promise<Response>): typeof fetch =>
  (async (input: string | URL | Request, init?: RequestInit) =>
    implementation(new URL(input instanceof Request ? input.url : input), init)) as typeof fetch;

describe('HttpConsoleOperations', () => {
  it('fans in enabled sources with partial failure reporting and bearer-only requests', async () => {
    // Arrange
    const requests: { readonly url: URL; readonly init: RequestInit | undefined }[] = [];
    const transport = asFetch(async (url, init) => {
      requests.push({ url, init });
      const landscape = url.hostname.startsWith('castform') ? 'castform' : 'serving';
      if (url.pathname.endsWith('/health')) return json(health(landscape));
      if (url.pathname.endsWith('/dlq')) {
        return json(
          deadLetterList(
            landscape,
            landscape === 'serving'
              ? [
                  {
                    landscape,
                    tenantId: 'tenant-1',
                    eventId: 'evt-1',
                    endpointId: 'endpoint-1',
                    jobId: 'job-1',
                    provider: 'stripe',
                    exhaustedAtMs: Date.parse('2026-07-29T00:59:00.000Z'),
                    reason: 'retry-window-exhausted',
                    attemptCount: 3,
                    finalOutcome: 503,
                  },
                ]
              : [],
          ),
        );
      }
      if (landscape === 'castform') {
        return json(
          {
            type: 'https://atomi.cloud/problems/mercury/storage-unavailable',
            title: 'Storage unavailable',
            status: 503,
            code: 'storage-unavailable',
            detail: `echoed secret ${TOKEN}`,
          },
          503,
        );
      }
      return json(eventList(landscape, [eventSummary(landscape)]));
    });
    const operations = new HttpConsoleOperations(new FakeGateway(), acceptingAuditor, {
      clock: new FixedClock(),
      fetch: transport,
      previewVisibility: {
        state: 'withheld-d11',
        detail: 'Callback-delivery visibility is withheld while route state remains visible.',
        affectedLandscapes: ['castform'],
      },
    });

    // Act
    const result = await operations.dashboard(authorization, { status: 'all' });

    // Assert
    should(result.ok).equal(true);
    if (!result.ok) throw new Error('Expected partial fan-in snapshot');
    should(result.value.intake).have.length(2);
    should(result.value.events).have.length(1);
    should(result.value.deadLetters).have.length(1);
    should(result.value.routes).have.length(1);
    should(result.value.sourceFailures).have.length(1);
    should(result.value.sourceFailures[0]?.landscape).equal('castform');
    should(result.value.previewVisibility.state).equal('withheld-d11');
    should(JSON.stringify(result.value)).not.containEql(TOKEN);
    should(requests).have.length(6);
    for (const request of requests) {
      should(new Headers(request.init?.headers).get('authorization')).equal(`Bearer ${TOKEN}`);
      should(new Headers(request.init?.headers).has('cookie')).equal(false);
      should(request.init?.credentials).equal('omit');
      should(request.init?.redirect).equal('error');
    }
  });

  it('rejects cross-account and origin-swapped trust records before bearer dispatch or durable audit', async () => {
    // Arrange
    const candidates: readonly ConsoleLandscapeSource[] = [
      {
        trustKind: 'account-owned',
        accountId: 'victim-account',
        landscape: 'serving',
        queryUrl: 'https://serving.example.test/query',
        queryOrigin: 'https://serving.example.test',
        replayUrl: 'https://serving.example.test/actions',
        replayOrigin: 'https://serving.example.test',
        enabled: true,
      },
      {
        trustKind: 'account-owned',
        accountId: authorization.accountId,
        landscape: 'serving',
        queryUrl: 'https://serving.example.test/query',
        queryOrigin: 'https://serving.example.test',
        replayUrl: 'https://attacker.example.test/actions',
        replayOrigin: 'https://serving.example.test',
        enabled: true,
      },
    ];

    for (const source of candidates) {
      let dispatches = 0;
      let audits = 0;
      const auditor: ConsoleActionAuditor = {
        async accept(): Promise<ConsoleResult<void>> {
          audits += 1;
          return { ok: true, value: undefined };
        },
      };
      const operations = new HttpConsoleOperations(new FakeGateway([source]), auditor, {
        clock: new FixedClock(),
        fetch: asFetch(async () => {
          dispatches += 1;
          return json({});
        }),
      });

      // Act
      const result = await operations.reenableEndpoint(authorization, {
        landscape: 'serving',
        endpointId: 'endpoint-1',
        audit: {
          requestId: 'request-12345678',
          sessionId: authorization.sessionId,
          accountId: authorization.accountId,
          reason: 'Circuit probe succeeded.',
        },
      });

      // Assert
      should(result.ok).equal(false);
      should(dispatches).equal(0);
      should(audits).equal(0);
      should(JSON.stringify(result)).not.containEql(TOKEN);
    }
  });

  it('bounds request concurrency and converts an aborted source into a partial timeout', async () => {
    // Arrange
    let active = 0;
    let maximumActive = 0;
    const transport = asFetch(async (url, init) => {
      active += 1;
      maximumActive = Math.max(maximumActive, active);
      try {
        if (url.hostname.startsWith('castform') && url.pathname.endsWith('/events')) {
          return await new Promise<Response>((_resolve, reject) => {
            init?.signal?.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')), {
              once: true,
            });
          });
        }
        await new Promise(resolve => setTimeout(resolve, 2));
        const landscape = url.hostname.startsWith('castform') ? 'castform' : 'serving';
        if (url.pathname.endsWith('/health')) return json(health(landscape));
        if (url.pathname.endsWith('/dlq')) return json(deadLetterList(landscape));
        return json(eventList(landscape, landscape === 'serving' ? [eventSummary()] : []));
      } finally {
        active -= 1;
      }
    });
    const operations = new HttpConsoleOperations(new FakeGateway(), acceptingAuditor, {
      clock: new FixedClock(),
      fetch: transport,
      timeoutMilliseconds: 20,
      maxConcurrency: 2,
    });

    // Act
    const result = await operations.dashboard(authorization, { status: 'all' });

    // Assert
    should(result.ok).equal(true);
    if (!result.ok) throw new Error('Expected bounded partial fan-in');
    should(maximumActive).be.belowOrEqual(2);
    should(result.value.sourceFailures).have.length(1);
    should(result.value.sourceFailures[0]?.detail).containEql('timed out');
  });

  it('withholds only affected callback-delivery health while retaining route and event state', async () => {
    // Arrange
    const transport = asFetch(async url => {
      const landscape = url.hostname.startsWith('castform') ? 'castform' : 'serving';
      if (url.pathname.endsWith('/health')) return json(health(landscape));
      if (url.pathname.endsWith('/dlq')) return json(deadLetterList(landscape));
      return json(eventList(landscape, [{ ...eventSummary(landscape), id: `evt-${landscape}`, status: 'completed' }]));
    });
    const operations = new HttpConsoleOperations(new FakeGateway(), acceptingAuditor, {
      clock: new FixedClock(),
      fetch: transport,
      previewVisibility: {
        state: 'withheld-d11',
        detail: 'Castform callback-delivery health is withheld.',
        affectedLandscapes: ['castform'],
      },
    });

    // Act
    const result = await operations.dashboard(authorization, { status: 'all' });

    // Assert
    should(result.ok).equal(true);
    if (!result.ok) throw new Error('Expected D11-scoped snapshot');
    should(result.value.events.map(item => item.landscape).sort()).deepEqual(['castform', 'serving']);
    should(result.value.routes.map(item => item.landscape).sort()).deepEqual(['castform', 'serving']);
    should(result.value.deliveries.map(item => item.landscape)).deepEqual(['serving']);
  });

  it('routes replay to the event source landscape and carries explicit audit context', async () => {
    // Arrange
    const requests: { readonly url: URL; readonly init: RequestInit | undefined }[] = [];
    const auditRequests: ConsoleActionAuditRequest[] = [];
    const ordering: string[] = [];
    const auditor: ConsoleActionAuditor = {
      async accept(request): Promise<ConsoleResult<void>> {
        ordering.push('audit');
        auditRequests.push(request);
        should(requests.some(value => value.init?.method === 'POST')).equal(false);
        return { ok: true, value: undefined };
      },
    };
    const transport = asFetch(async (url, init) => {
      requests.push({ url, init });
      if (init?.method === 'POST') {
        ordering.push('dispatch');
        return json(
          {
            actionId: 'action-1',
            action: 'event-replayed',
            landscape: 'serving',
            tenantId: 'tenant-1',
            acceptedAtMs: Date.parse('2026-07-29T01:00:00.000Z'),
            affectedCount: 1,
          },
          202,
        );
      }
      return json(detail());
    });
    const operations = new HttpConsoleOperations(new FakeGateway(), auditor, {
      clock: new FixedClock(),
      fetch: transport,
    });

    // Act
    const result = await operations.replayEvent(authorization, {
      landscape: 'serving',
      eventId: 'evt-1',
      endpointId: 'endpoint-1',
      audit: {
        requestId: 'request-12345678',
        sessionId: authorization.sessionId,
        accountId: authorization.accountId,
        reason: 'Receiver recovered after incident.',
      },
    });

    // Assert
    should(result.ok).equal(true);
    const action = requests.find(request => request.init?.method === 'POST');
    should(action).not.equal(undefined);
    should(action?.url.hostname).equal('serving.example.test');
    should(action?.url.pathname).equal('/actions/tenants/tenant-1/events/evt-1/replay');
    should(requests.some(request => request.url.hostname === 'castform.example.test')).equal(false);
    const body = JSON.parse(String(action?.init?.body)) as {
      readonly endpointId: string;
      readonly audit: { readonly accountId: string; readonly reason: string };
    };
    should(body.endpointId).equal('endpoint-1');
    should(body.audit.accountId).equal('account-1');
    should(body.audit.reason).equal('Receiver recovered after incident.');
    should(ordering).deepEqual(['audit', 'dispatch']);
    should(auditRequests).have.length(1);
    should(auditRequests[0]?.tenantId).equal('tenant-1');
    should(auditRequests[0]?.landscape).equal('serving');
    should(auditRequests[0]?.target).deepEqual({
      kind: 'event-replay',
      eventId: 'evt-1',
      endpointId: 'endpoint-1',
    });
    should(auditRequests[0]?.context.reason).equal('Receiver recovered after incident.');
    should(auditRequests[0]?.authorization.scope.tenants).deepEqual(['tenant-1']);
    should(JSON.stringify(auditRequests[0]?.authorization)).not.containEql(TOKEN);
  });

  it('audits endpoint replay and circuit re-enable before each landscape dispatch', async () => {
    // Arrange
    const ordering: string[] = [];
    const auditRequests: ConsoleActionAuditRequest[] = [];
    const auditor: ConsoleActionAuditor = {
      async accept(request): Promise<ConsoleResult<void>> {
        ordering.push('audit');
        auditRequests.push(request);
        return { ok: true, value: undefined };
      },
    };
    const transport = asFetch(async (url, init) => {
      if (init?.method === 'POST') {
        ordering.push('dispatch');
        const circuit = url.pathname.endsWith('/circuit/re-enable');
        return json(
          {
            actionId: circuit ? 'action-circuit' : 'action-endpoint',
            action: circuit ? 'circuit-reenabled' : 'endpoint-replayed',
            landscape: 'serving',
            tenantId: 'tenant-1',
            acceptedAtMs: Date.parse('2026-07-29T01:00:00.000Z'),
            affectedCount: circuit ? 1 : 3,
          },
          202,
        );
      }
      if (url.pathname.endsWith('/dlq')) {
        return json(
          deadLetterList('serving', [
            {
              landscape: 'serving',
              tenantId: 'tenant-1',
              eventId: 'evt-1',
              endpointId: 'endpoint-1',
              jobId: 'job-1',
              exhaustedAtMs: Date.parse('2026-07-29T00:59:00.000Z'),
              reason: 'retry-window-exhausted',
              attemptCount: 3,
            },
          ]),
        );
      }
      return json(eventList('serving', [{ ...eventSummary(), status: 'paused' }]));
    });
    const operations = new HttpConsoleOperations(new FakeGateway(), auditor, {
      clock: new FixedClock(),
      fetch: transport,
    });
    const context = {
      requestId: 'request-12345678',
      sessionId: authorization.sessionId,
      accountId: authorization.accountId,
      reason: 'Reviewed retained obligations.',
    };

    // Act
    const replayed = await operations.replayEndpoint(authorization, {
      landscape: 'serving',
      endpointId: 'endpoint-1',
      audit: context,
    });
    const reenabled = await operations.reenableEndpoint(authorization, {
      landscape: 'serving',
      endpointId: 'endpoint-1',
      audit: { ...context, requestId: 'request-87654321' },
    });

    // Assert
    should(replayed.ok).equal(true);
    should(reenabled.ok).equal(true);
    should(ordering).deepEqual(['audit', 'dispatch', 'audit', 'dispatch']);
    should(auditRequests.map(request => request.target)).deepEqual([
      { kind: 'endpoint-replay', endpointId: 'endpoint-1' },
      { kind: 'circuit-reenable', endpointId: 'endpoint-1' },
    ]);
    should(auditRequests.every(request => request.tenantId === 'tenant-1')).equal(true);
  });

  it('fails closed without a remote mutation when durable action audit is rejected', async () => {
    // Arrange
    let postCount = 0;
    const auditRequests: ConsoleActionAuditRequest[] = [];
    const auditor: ConsoleActionAuditor = {
      async accept(request): Promise<ConsoleResult<void>> {
        auditRequests.push(request);
        return {
          ok: false,
          error: {
            kind: 'unavailable',
            title: 'Durable audit unavailable',
            detail: 'No mutation was accepted.',
          },
        };
      },
    };
    const transport = asFetch(async (url, init) => {
      if (init?.method === 'POST') {
        postCount += 1;
        return json({});
      }
      if (url.pathname.endsWith('/dlq')) return json(deadLetterList('serving'));
      return json(eventList('serving', [{ ...eventSummary(), status: 'paused' }]));
    });
    const operations = new HttpConsoleOperations(new FakeGateway(), auditor, {
      clock: new FixedClock(),
      fetch: transport,
    });

    // Act
    const result = await operations.reenableEndpoint(authorization, {
      landscape: 'serving',
      endpointId: 'endpoint-1',
      audit: {
        requestId: 'request-12345678',
        sessionId: authorization.sessionId,
        accountId: authorization.accountId,
        reason: 'Circuit probe succeeded.',
      },
    });

    // Assert
    should(result.ok).equal(false);
    should(postCount).equal(0);
    should(auditRequests).have.length(1);
    should(auditRequests[0]?.target).deepEqual({
      kind: 'circuit-reenable',
      endpointId: 'endpoint-1',
    });
  });

  it('redacts the short-lived bearer from authenticated event DTO content', async () => {
    // Arrange
    const transport = asFetch(async () => json(detail(TOKEN)));
    const operations = new HttpConsoleOperations(new FakeGateway(), acceptingAuditor, {
      clock: new FixedClock(),
      fetch: transport,
    });

    // Act
    const result = await operations.event(authorization, 'serving', 'evt-1');

    // Assert
    should(result.ok).equal(true);
    if (!result.ok) throw new Error('Expected event detail');
    should(JSON.stringify(result.value)).not.containEql(TOKEN);
    should(result.value.allowedHeaders).not.have.property('authorization');
    should(result.value.payload).containEql('[REDACTED AUTHORIZATION]');
    should(result.value.deliveryAddress).containEql('[REDACTED AUTHORIZATION]');
  });
});
