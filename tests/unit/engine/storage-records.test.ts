import { describe, it } from 'bun:test';
import should from 'should';
import { ScriptedDeliveryTransport, ScriptedEndpointRefresher } from '../../../src/delivery/fakes.ts';
import type {
  CompiledEndpoint,
  DeliveryFailure,
  DeliveryJob,
  EndpointRefreshRequest,
  LandscapeRuntimeConfig,
  RetainedEventQuery,
  WebhookEnvelope,
} from '../../../src/domain/index.ts';
import {
  decodeEnvelope,
  decodeJob,
  decodeRuntimeConfig,
  encodeEnvelope,
  encodeEventArchivePage,
  encodeJob,
  encodeRuntimeConfig,
  eventMonth,
} from '../../../src/storage/codec.ts';
import {
  retainedEventLimit,
  retainedEventMatches,
  retainedEventOffset,
  retainedEventRecord,
} from '../../../src/storage/retained-events.ts';

const encoder = new TextEncoder();

const envelope = (overrides: Partial<WebhookEnvelope> = {}): WebhookEnvelope => ({
  id: 'event-123',
  tenantId: 'tenant-acme',
  routeId: 'billing',
  provider: 'stripe',
  landingLandscape: 'raichu',
  receivedAtMs: Date.UTC(2026, 0, 15, 12),
  providerEventId: 'provider-123',
  dedupId: 'dedup-123',
  rawBody: new Uint8Array([0, 1, 255, 34]),
  headers: { 'content-type': 'application/json' },
  verificationMetadata: { signature: 'verified' },
  obligations: [
    {
      id: 'job-123',
      endpointId: 'endpoint-primary',
      address: 'https://receiver.example/webhooks',
      addressKind: 'canonical',
      signingSecretRef: 'delivery/acme-primary',
    },
  ],
  ...overrides,
});

const job = (overrides: Partial<DeliveryJob> = {}): DeliveryJob => ({
  id: 'job-123',
  eventId: 'event-123',
  tenantId: 'tenant-acme',
  routeId: 'billing',
  endpointId: 'endpoint-primary',
  address: 'https://receiver.example/webhooks',
  addressKind: 'canonical',
  signingSecretRef: 'delivery/acme-primary',
  createdAtMs: Date.UTC(2026, 0, 15, 12),
  dueAtMs: Date.UTC(2026, 0, 15, 12),
  retryWindowMs: 60_000,
  status: 'pending',
  attempts: [],
  misrouteRefreshes: 0,
  replayCount: 0,
  ...overrides,
});

const endpoint = (overrides: Partial<CompiledEndpoint> = {}): CompiledEndpoint => ({
  id: 'endpoint-primary',
  address: 'https://receiver.example/webhooks',
  addressKind: 'canonical',
  canonicalUrl: 'https://receiver.example/webhooks',
  signingSecretRef: 'delivery/acme-primary',
  ...overrides,
});

const runtimeConfig = (): LandscapeRuntimeConfig => ({
  generation: 7,
  landscape: 'raichu',
  compiledAtMs: Date.UTC(2026, 0, 15, 12),
  sourceRevision: 'revision-123',
  tenants: [
    {
      id: 'tenant-acme',
      slug: 'acme',
      registeredDomains: ['hooks.acme.example'],
      intakeRps: 10,
      intakeBurst: 20,
      retryWindowMs: 60_000,
      routes: [
        {
          id: 'billing',
          path: '/webhooks/billing',
          canonicalPath: '/t/acme/webhooks/billing',
          provider: 'stripe',
          registeredUrl: 'https://hooks.acme.example/webhooks/billing',
          verificationSecretRefs: ['verify/acme-primary', 'verify/acme-overlap'],
          endpoints: [endpoint()],
        },
      ],
    },
  ],
});

describe('retained event records', () => {
  it('should apply every status precedence rule', () => {
    const cases: readonly [string, readonly DeliveryJob[], string][] = [
      [
        'dead letters ahead of all other states',
        [job({ status: 'dead-letter' }), job({ status: 'paused' })],
        'dead-letter',
      ],
      [
        'paused jobs ahead of completed and retrying jobs',
        [job({ status: 'paused' }), job({ attempts: [{} as never] })],
        'paused',
      ],
      ['no jobs as completed', [], 'completed'],
      ['all completed jobs as completed', [job({ status: 'completed' }), job({ status: 'completed' })], 'completed'],
      ['attempted pending jobs as retrying', [job({ attempts: [{} as never] })], 'retrying'],
      ['unattempted pending jobs as pending', [job()], 'pending'],
    ];

    for (const [name, jobs, status] of cases) {
      should(retainedEventRecord(envelope(), jobs).status).equal(status, name);
    }
  });

  it('should match every query filter with inclusive received-time bounds', () => {
    const receivedAtMs = Date.UTC(2026, 0, 15, 12);
    const record = retainedEventRecord(envelope({ receivedAtMs }), [
      job({ status: 'pending', attempts: [{} as never] }),
      job({ endpointId: 'endpoint-secondary' }),
    ]);
    const matching: RetainedEventQuery = {
      tenantId: 'tenant-acme',
      provider: 'stripe',
      routeId: 'billing',
      endpointId: 'endpoint-secondary',
      status: 'retrying',
      receivedAfterMs: receivedAtMs,
      receivedBeforeMs: receivedAtMs,
    };

    should(retainedEventMatches(record, matching)).be.true();
    should(retainedEventMatches(record, { tenantId: 'tenant-acme', provider: 'github' })).be.false();
    should(retainedEventMatches(record, { tenantId: 'tenant-acme', routeId: 'other' })).be.false();
    should(retainedEventMatches(record, { tenantId: 'tenant-acme', endpointId: 'endpoint-missing' })).be.false();
    should(retainedEventMatches(record, { tenantId: 'tenant-acme', status: 'pending' })).be.false();
    should(retainedEventMatches(record, { tenantId: 'tenant-acme', receivedAfterMs: receivedAtMs + 1 })).be.false();
    should(retainedEventMatches(record, { tenantId: 'tenant-acme', receivedBeforeMs: receivedAtMs - 1 })).be.false();
  });

  it('should accept only canonical safe-integer cursors', () => {
    should(retainedEventOffset(undefined)).equal(0);
    should(retainedEventOffset('0')).equal(0);
    should(retainedEventOffset('42')).equal(42);
    should(retainedEventOffset(String(Number.MAX_SAFE_INTEGER))).equal(Number.MAX_SAFE_INTEGER);

    for (const cursor of ['', '00', '01', '-0', '-1', '+1', '1.0', '1e2', ' 1', '1 ', '9007199254740992']) {
      should(retainedEventOffset(cursor)).equal(null, cursor);
    }
  });

  it('should default and bound retained-event limits', () => {
    should(retainedEventLimit(undefined)).equal(50);
    should(retainedEventLimit(1)).equal(1);
    should(retainedEventLimit(200)).equal(200);

    for (const limit of [0, 201, -1, 1.5, Number.NaN, Number.POSITIVE_INFINITY]) {
      should(retainedEventLimit(limit)).equal(null, String(limit));
    }
  });
});

describe('storage codecs', () => {
  it('should base64 round-trip envelope bytes without persisting a duplicate raw body', () => {
    const source = envelope();
    const encoded = encodeEnvelope(source);
    const stored = JSON.parse(encoded) as Record<string, unknown>;

    should(stored.rawBody).be.undefined();
    should(stored.rawBodyBase64).equal('AAH/Ig==');
    const decoded = decodeEnvelope(encoded);
    should(decoded).match(source);
    should([...decoded.rawBody]).deepEqual([...source.rawBody]);
  });

  it('should round-trip delivery jobs and runtime configuration', () => {
    const sourceJob = job({
      attempts: [
        {
          number: 1,
          attemptedAtMs: 1,
          address: 'https://receiver.example/webhooks',
          signatureTimestampSeconds: 2,
          statusCode: 503,
          replay: true,
        },
      ],
    });
    const sourceConfig = runtimeConfig();

    should(decodeJob(encodeJob(sourceJob))).deepEqual(sourceJob);
    should(decodeRuntimeConfig(encodeRuntimeConfig(sourceConfig))).deepEqual(sourceConfig);
  });

  it('should encode archive metadata, bodies, and dead letters', () => {
    const source = envelope();
    const sourceJob = job({ status: 'dead-letter' });
    const page = JSON.parse(
      new TextDecoder().decode(
        encodeEventArchivePage('raichu', 'tenant-acme', '2026-01', 3, [
          {
            envelope: source,
            jobs: [sourceJob],
            deadLetters: [
              {
                landscape: 'raichu',
                tenantId: 'tenant-acme',
                eventId: source.id,
                endpointId: sourceJob.endpointId,
                jobId: sourceJob.id,
                exhaustedAtMs: source.receivedAtMs + 1,
                reason: 'retries exhausted',
              },
            ],
          },
        ]),
      ),
    ) as Record<string, unknown>;
    const records = page.records as Array<Record<string, unknown>>;
    const archivedEnvelope = records[0]?.envelope as Record<string, unknown>;

    should(page).match({
      schema: 'mercury.event-archive-part.v1',
      landscape: 'raichu',
      tenantId: 'tenant-acme',
      month: '2026-01',
      version: 3,
    });
    should(records).have.length(1);
    should(archivedEnvelope.rawBody).be.undefined();
    should(archivedEnvelope.rawBodyBase64).equal('AAH/Ig==');
    should(records[0]?.jobs).deepEqual([sourceJob]);
    should(records[0]?.deadLetters).match([{ reason: 'retries exhausted' }]);
  });

  it('should derive UTC event months and reject malformed JSON input', () => {
    should(eventMonth(Date.UTC(2026, 0, 1))).equal('2026-01');
    should(eventMonth(Date.UTC(2025, 11, 31, 23, 59, 59, 999))).equal('2025-12');

    for (const decode of [decodeEnvelope, decodeJob, decodeRuntimeConfig]) {
      should(() => decode('{')).throw();
    }
  });
});

describe('scripted delivery fakes', () => {
  it('should default, consume scripted successes and failures, and copy delivery requests', async () => {
    const subject = new ScriptedDeliveryTransport();
    const body = encoder.encode('original');
    const headers = { 'x-request-id': 'original' };
    subject.set('https://scripted.example/webhooks', [
      { status: 202 },
      { error: { code: 'network', message: 'offline' } },
    ]);

    const defaultResult = await subject.send({ url: 'https://default.example/webhooks', body, headers });
    const success = await subject.send({ url: 'https://scripted.example/webhooks', body, headers });
    const failure = await subject.send({ url: 'https://scripted.example/webhooks', body, headers });
    const exhaustedScript = await subject.send({ url: 'https://scripted.example/webhooks', body, headers });
    body[0] = 0;
    headers['x-request-id'] = 'mutated';

    should(await defaultResult.unwrap()).match({ status: 200, headers: {} });
    should(await success.unwrap()).match({ status: 202, headers: {} });
    should(await failure.isErr()).be.true();
    should(await failure.unwrapErr()).deepEqual({ code: 'network', message: 'offline' });
    should(await exhaustedScript.unwrap()).match({ status: 200, headers: {} });
    should(subject.requests).have.length(4);
    should(new TextDecoder().decode(subject.requests[0]?.body)).equal('original');
    should(subject.requests[0]?.headers).deepEqual({ 'x-request-id': 'original' });
  });

  it('should return scripted endpoint refreshes and retain refresh requests', async () => {
    const refreshed = endpoint({ id: 'endpoint-refreshed' });
    const subject = new ScriptedEndpointRefresher(refreshed);
    const request: EndpointRefreshRequest = {
      tenantId: 'tenant-acme',
      routeId: 'billing',
      endpointId: 'endpoint-primary',
    };

    const success = await subject.refreshEndpoint(request);
    const failure: DeliveryFailure = { code: 'config-unavailable', message: 'configuration is unavailable' };
    subject.failure = failure;
    const failed = await subject.refreshEndpoint(request);

    should(await success.unwrap()).deepEqual(refreshed);
    should(await failed.isErr()).be.true();
    should(await failed.unwrapErr()).deepEqual(failure);
    should(subject.requests).deepEqual([request, request]);
  });
});
