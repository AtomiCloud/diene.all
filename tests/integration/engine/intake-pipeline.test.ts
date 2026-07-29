import { describe, it } from 'bun:test';
import { Err, Ok } from '@atomicloud/diene.result';
import should from 'should';
import {
  DEDUP_WINDOW_SECONDS,
  MERCURY_MAX_REQUEST_BODY_BYTES,
  NameBlindRouteResolver,
  type RegistrationSnapshot,
} from '../../../src/domain/index.ts';
import { IntakeHttpAdapter } from '../../../src/http/intake/adapter.ts';
import { defaultIntakePortal, IntakeProblemCatalog } from '../../../src/http/intake/problems.ts';
import { MAX_ENDPOINTS_PER_ROUTE } from '../../../src/runtime/config.ts';
import { MercuryConfigCompiler } from '../../../src/runtime/config-compiler.ts';
import {
  ManualClock,
  MemorySnapshotSource,
  MemoryTelemetry,
  ProviderVerifierMap,
  SequenceIdentifierFactory,
} from '../../../src/runtime/fakes.ts';
import { IntakeEngine } from '../../../src/runtime/intake-engine.ts';
import { MemoryLandscapeStore } from '../../../src/storage/memory.ts';

const decoder = new TextDecoder();

const registrationSnapshot = (burst = 1_000): RegistrationSnapshot => ({
  revision: 'intake-1',
  tenants: [
    {
      id: 'external/acme',
      slug: 'acme',
      registeredDomains: ['hooks.acme.example'],
      intakeRps: 1_000,
      intakeBurst: burst,
      retryWindowMs: 72 * 60 * 60 * 1_000,
      routes: [
        {
          id: 'paid',
          path: '/stripe/paid',
          provider: 'stripe',
          registeredUrl: 'https://hooks.acme.example/stripe/paid',
          verificationSecretRef: 'verify/acme',
          endpoints: [
            {
              id: 'local',
              targetKind: 'coordinate',
              canonicalUrl: 'https://checkout.acme.mew.cluster.atomi.cloud/internal/webhooks/stripe',
              localUrls: {
                raichu: 'http://checkout.acme.svc.cluster.local/internal/webhooks/stripe',
              },
              signingSecretRef: 'delivery/acme',
            },
            {
              id: 'remote',
              targetKind: 'coordinate',
              canonicalUrl: 'https://checkout.acme.celebi.cluster.atomi.cloud/internal/webhooks/stripe',
              localUrls: {
                ampharos: 'http://checkout.acme.svc.cluster.local/internal/webhooks/stripe',
              },
              signingSecretRef: 'delivery/acme',
            },
            {
              id: 'customer',
              targetKind: 'external',
              canonicalUrl: 'https://customer.example/webhooks/stripe',
              localUrls: {},
              signingSecretRef: 'delivery/customer',
            },
          ],
        },
        {
          id: 'refunded',
          path: '/stripe/refunded',
          provider: 'stripe',
          registeredUrl: 'https://hooks.acme.example/stripe/refunded',
          verificationSecretRef: 'verify/acme',
          endpoints: [],
        },
      ],
    },
    {
      id: 'external/other',
      slug: 'other',
      registeredDomains: ['hooks.other.example'],
      intakeRps: 1_000,
      intakeBurst: 1_000,
      retryWindowMs: 72 * 60 * 60 * 1_000,
      routes: [
        {
          id: 'paid',
          path: '/stripe/paid',
          provider: 'stripe',
          registeredUrl: 'https://hooks.other.example/stripe/paid',
          verificationSecretRef: 'verify/other',
          endpoints: [],
        },
      ],
    },
  ],
});

interface Harness {
  readonly adapter: IntakeHttpAdapter;
  readonly clock: ManualClock;
  readonly compiler: MercuryConfigCompiler;
  readonly durableOrder: string[];
  readonly source: MemorySnapshotSource;
  readonly store: MemoryLandscapeStore;
  readonly telemetry: MemoryTelemetry;
  readonly verificationReferenceSets: string[][];
  readonly verificationUrls: string[];
}

const createHarness = async (landscape = 'raichu', burst = 1_000): Promise<Harness> => {
  const clock = new ManualClock(Date.UTC(2026, 0, 10));
  const durableOrder: string[] = [];
  const store = new MemoryLandscapeStore(landscape, clock, eventId => durableOrder.push(`durable:${eventId}`));
  const source = new MemorySnapshotSource(registrationSnapshot(burst));
  const telemetry = new MemoryTelemetry();
  const verificationReferenceSets: string[][] = [];
  const verificationUrls: string[] = [];
  const compiler = new MercuryConfigCompiler(landscape, source, store, clock, telemetry);
  await (await compiler.compile()).unwrap();
  const verifier = new ProviderVerifierMap({
    stripe: async input => {
      verificationReferenceSets.push(
        input.verificationSecretRefs === undefined
          ? input.verificationSecretRef === undefined
            ? []
            : [input.verificationSecretRef]
          : [...input.verificationSecretRefs],
      );
      verificationUrls.push(input.registeredUrl);
      if (input.headers['x-provider-signature'] === 'missing') {
        return Err({
          code: 'missing-credential' as const,
          message: 'mounted verifier material is unavailable',
        });
      }
      if (input.headers['x-provider-signature'] === 'explode') {
        throw new Error('unexpected verifier defect');
      }
      if (input.headers['x-provider-signature'] !== 'valid') {
        return Err({
          code: 'invalid-signature' as const,
          message: 'forged provider signature',
        });
      }
      return Ok({
        ...(input.headers['x-provider-event-id'] === undefined
          ? {}
          : { providerEventId: input.headers['x-provider-event-id'] }),
        providerTimestampMs: 1_700_000_000_000,
        providerSequence: input.headers['x-provider-sequence'] ?? 'sequence-1',
        signatureMaterial: input.headers['x-provider-signature'],
        metadata: { verifier: 'stripe-test' },
      });
    },
  });
  const identifiers = new SequenceIdentifierFactory(
    Array.from({ length: 100 }, (_, index) => `event-${landscape}-${index + 1}`),
  );
  const engine = new IntakeEngine(store, store, verifier, new NameBlindRouteResolver(), clock, identifiers, telemetry);
  const adapter = new IntakeHttpAdapter(engine, new IntakeProblemCatalog(defaultIntakePortal));
  return {
    adapter,
    clock,
    compiler,
    durableOrder,
    source,
    store,
    telemetry,
    verificationReferenceSets,
    verificationUrls,
  };
};

const request = (
  path: string,
  eventId: string | undefined,
  body = '{"type":"invoice.paid"}',
  signature = 'valid',
  host = 'untrusted.example',
): Request =>
  new Request(`https://${host}${path}`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-forwarded-host': 'hooks.other.example',
      'x-provider-signature': signature,
      'x-provider-sequence': 'provider-sequence-7',
      ...(eventId === undefined ? {} : { 'x-provider-event-id': eventId }),
    },
    body,
  });

describe('intake HTTP pipeline', () => {
  it('should return 404/401/503 without persistence and 429 with Retry-After', async () => {
    // Arrange
    const unknownHarness = await createHarness();
    const verificationHarness = await createHarness();
    const persistenceHarness = await createHarness();
    const quotaHarness = await createHarness('raichu', 1);
    persistenceHarness.store.failNext('accept-once', 'Upstash unavailable');

    // Act
    const unknown = await unknownHarness.adapter.handle(request('/t/acme/missing', 'evt-unknown'));
    const unauthorized = await verificationHarness.adapter.handle(
      request('/t/acme/stripe/paid', 'evt-forged', '{}', 'forged'),
    );
    const unavailable = await persistenceHarness.adapter.handle(request('/t/acme/stripe/paid', 'evt-fail'));
    const firstQuota = await quotaHarness.adapter.handle(request('/t/acme/stripe/paid', 'evt-first'));
    const exhausted = await quotaHarness.adapter.handle(request('/t/acme/stripe/paid', 'evt-second'));
    const [unknownProblem, verificationProblem, persistenceProblem, quotaProblem] = (await Promise.all([
      unknown.clone().json(),
      unauthorized.clone().json(),
      unavailable.clone().json(),
      exhausted.clone().json(),
    ])) as Array<{ readonly type: string }>;

    // Assert
    should(unknown.status).equal(404);
    should(unknownHarness.store.events.size).equal(0);
    should(unauthorized.status).equal(401);
    should(verificationHarness.store.events.size).equal(0);
    should(unavailable.status).equal(503);
    should(persistenceHarness.store.events.size).equal(0);
    should(persistenceHarness.store.dedupExpiries.size).equal(0);
    should(firstQuota.status).equal(200);
    should(exhausted.status).equal(429);
    should(Number(exhausted.headers.get('retry-after'))).be.above(0);
    should(quotaHarness.store.events.size).equal(1);
    should(unknownProblem?.type).endWith('/v1/unknown_route');
    should(verificationProblem?.type).endWith('/v1/verification_failed');
    should(persistenceProblem?.type).endWith('/v1/persistence_unavailable');
    should(quotaProblem?.type).endWith('/v1/quota_exhausted');
    should(unknownProblem?.type).startWith('https://problems.atomi.cloud/docs/serving/mercury/webhook/hooks/');
  });

  it('should verify before consuming quota so forged traffic cannot exhaust a tenant', async () => {
    // Arrange
    const harness = await createHarness('raichu', 1);

    // Act
    const forged = await harness.adapter.handle(request('/t/acme/stripe/paid', 'evt-forged', '{}', 'forged'));
    const accepted = await harness.adapter.handle(request('/t/acme/stripe/paid', 'evt-valid'));
    const exhausted = await harness.adapter.handle(request('/t/acme/stripe/paid', 'evt-next'));

    // Assert
    should(forged.status).equal(401);
    should(accepted.status).equal(200);
    should(exhausted.status).equal(429);
    should(harness.store.events.size).equal(1);
  });

  it('should return retryable 503 for verifier configuration, unsupported-provider, and unexpected failures', async () => {
    // Arrange
    const missingHarness = await createHarness();
    const unexpectedHarness = await createHarness();
    const unsupportedHarness = await createHarness();
    const configHarness = await createHarness();
    Object.defineProperty(configHarness.store, 'readActive', {
      configurable: true,
      value: async () => {
        throw new Error('unexpected configuration reader defect');
      },
    });
    unsupportedHarness.source.snapshot = {
      ...unsupportedHarness.source.snapshot,
      revision: 'unsupported-provider',
      tenants: unsupportedHarness.source.snapshot.tenants.map(tenant => ({
        ...tenant,
        routes: tenant.routes.map(route => ({ ...route, provider: 'cloudflare' })),
      })),
    };
    await (await unsupportedHarness.compiler.compile()).unwrap();

    // Act
    const missing = await missingHarness.adapter.handle(
      request('/t/acme/stripe/paid', 'evt-missing-config', '{}', 'missing'),
    );
    const unexpected = await unexpectedHarness.adapter.handle(
      request('/t/acme/stripe/paid', 'evt-verifier-defect', '{}', 'explode'),
    );
    const unsupported = await unsupportedHarness.adapter.handle(
      request('/t/acme/stripe/paid', 'evt-unsupported', '{}', 'valid'),
    );
    const configUnavailable = await configHarness.adapter.handle(
      request('/t/acme/stripe/paid', 'evt-config-defect', '{}', 'valid'),
    );
    const problems = (await Promise.all([
      missing.clone().json(),
      unexpected.clone().json(),
      unsupported.clone().json(),
      configUnavailable.clone().json(),
    ])) as Array<{ readonly detail: string; readonly type: string }>;

    // Assert
    should([missing.status, unexpected.status, unsupported.status, configUnavailable.status]).deepEqual([
      503, 503, 503, 503,
    ]);
    should(problems.every(problem => problem.type.endsWith('/v1/persistence_unavailable'))).be.true();
    should(problems.some(problem => problem.detail.includes('unexpected configuration reader defect'))).be.false();
    should(problems.some(problem => problem.detail.includes('mounted verifier material'))).be.false();
    should(problems.some(problem => problem.detail.includes('unexpected verifier defect'))).be.false();
    should(missingHarness.store.events.size).equal(0);
    should(unexpectedHarness.store.events.size).equal(0);
    should(unsupportedHarness.store.events.size).equal(0);
    should(configHarness.store.events.size).equal(0);
    should(missingHarness.telemetry.events.some(event => event.name === 'verification.failure')).be.false();
    should(unexpectedHarness.telemetry.events.some(event => event.name === 'verification.failure')).be.false();
  });

  it('should preserve ordered live and overlap verification references with singular fallback', async () => {
    // Arrange
    const harness = await createHarness();
    const active = await (await harness.store.readActive()).unwrap();
    const tenant = active?.tenants[0];
    const route = tenant?.routes[0];
    should(active).not.be.null();
    should(tenant).not.be.undefined();
    should(route).not.be.undefined();
    harness.store.configGenerations.set((active as NonNullable<typeof active>).generation, {
      ...(active as NonNullable<typeof active>),
      tenants: [
        {
          ...(tenant as NonNullable<typeof tenant>),
          routes: [
            {
              ...(route as NonNullable<typeof route>),
              verificationSecretRefs: ['verify/current', 'verify/overlap'],
            },
          ],
        },
      ],
    });

    // Act
    const response = await harness.adapter.handle(request('/t/acme/stripe/paid', 'evt-rotation'));

    // Assert
    should(response.status).equal(200);
    should(harness.verificationReferenceSets).deepEqual([['verify/current', 'verify/overlap']]);
  });

  it('should cancel and return 413 before route lookup when an unknown-route stream crosses the byte limit', async () => {
    // Arrange
    const harness = await createHarness();
    let cancelled = false;
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new Uint8Array(MERCURY_MAX_REQUEST_BODY_BYTES));
        controller.enqueue(Uint8Array.of(1));
      },
      cancel() {
        cancelled = true;
      },
    });
    const oversized = new Request('https://untrusted.example/t/acme/missing', {
      method: 'POST',
      body: stream,
    });

    // Act
    const response = await harness.adapter.handle(oversized);
    const problem = (await response.json()) as { readonly status: number };

    // Assert
    should(response.status).equal(413);
    should(problem.status).equal(413);
    should(cancelled).be.true();
    should(harness.telemetry.events.some(event => event.name === 'route.unknown')).be.false();
    should(harness.store.events.size).equal(0);
  });

  it('should accept exactly the bounded byte count and cancel a declared oversized body without pulling it', async () => {
    // Arrange
    const exactHarness = await createHarness();
    const declaredHarness = await createHarness();
    let pulls = 0;
    let cancelled = false;
    const declaredStream = new ReadableStream<Uint8Array>(
      {
        pull(controller) {
          pulls += 1;
          controller.enqueue(Uint8Array.of(1));
        },
        cancel() {
          cancelled = true;
        },
      },
      { highWaterMark: 0 },
    );

    // Act
    const exact = await exactHarness.adapter.handle(
      new Request('https://untrusted.example/t/acme/missing', {
        method: 'POST',
        body: new Uint8Array(MERCURY_MAX_REQUEST_BODY_BYTES),
      }),
    );
    const declared = await declaredHarness.adapter.handle(
      new Request('https://untrusted.example/t/acme/missing', {
        method: 'POST',
        headers: { 'content-length': String(MERCURY_MAX_REQUEST_BODY_BYTES + 1) },
        body: declaredStream,
      }),
    );

    // Assert
    should(exact.status).equal(404);
    should(declared.status).equal(413);
    should(pulls).equal(0);
    should(cancelled).be.true();
  });

  it('should cancel a body reader when the client aborts during streaming', async () => {
    // Arrange
    const harness = await createHarness();
    const controller = new AbortController();
    let cancelled = false;
    const stream = new ReadableStream<Uint8Array>({
      pull: () => new Promise<void>(() => undefined),
      cancel() {
        cancelled = true;
      },
    });
    const pending = harness.adapter.handle(
      new Request('https://untrusted.example/t/acme/missing', {
        method: 'POST',
        body: stream,
        signal: controller.signal,
      }),
    );

    // Act
    controller.abort(new DOMException('client disconnected', 'AbortError'));
    const response = await pending;

    // Assert
    should(response.status).equal(503);
    should(cancelled).be.true();
    should(harness.telemetry.events.some(event => event.name === 'route.unknown')).be.false();
  });

  it('should reject an oversized atomic fan-out command before persistence', async () => {
    // Arrange
    const harness = await createHarness();
    const tenant = harness.source.snapshot.tenants[0];
    const route = tenant?.routes[0];
    const endpoint = route?.endpoints[2];
    should(tenant).not.be.undefined();
    should(route).not.be.undefined();
    should(endpoint).not.be.undefined();
    const longPath = 'a'.repeat(15_000);
    harness.source.snapshot = {
      revision: 'large-but-compiled',
      tenants: [
        {
          ...(tenant as NonNullable<typeof tenant>),
          routes: [
            {
              ...(route as NonNullable<typeof route>),
              endpoints: Array.from({ length: MAX_ENDPOINTS_PER_ROUTE }, (_, index) => ({
                ...(endpoint as NonNullable<typeof endpoint>),
                id: `endpoint-${index}`,
                canonicalUrl: `https://customer.example/${longPath}-${index}`,
                signingSecretRef: `delivery/${longPath}-${index}`,
              })),
            },
          ],
        },
      ],
    };
    await (await harness.compiler.compile()).unwrap();

    // Act
    const response = await harness.adapter.handle(
      request('/t/acme/stripe/paid', 'evt-command-bound', 'x'.repeat(MERCURY_MAX_REQUEST_BODY_BYTES)),
    );

    // Assert
    should(response.status).equal(503);
    should(harness.store.events.size).equal(0);
    should(harness.store.dedupExpiries.size).equal(0);
    should(
      harness.telemetry.events.some(
        event => event.name === 'intake.unavailable' && event.attributes.operation === 'fanout-bounds',
      ),
    ).be.true();
  });

  it('should reject a bypassed active generation whose endpoint array exceeds the runtime cap', async () => {
    // Arrange
    const harness = await createHarness();
    const active = await (await harness.store.readActive()).unwrap();
    const tenant = active?.tenants[0];
    const route = tenant?.routes[0];
    const endpoint = route?.endpoints[0];
    should(active).not.be.null();
    should(tenant).not.be.undefined();
    should(route).not.be.undefined();
    should(endpoint).not.be.undefined();
    harness.store.configGenerations.set((active as NonNullable<typeof active>).generation, {
      ...(active as NonNullable<typeof active>),
      tenants: [
        {
          ...(tenant as NonNullable<typeof tenant>),
          routes: [
            {
              ...(route as NonNullable<typeof route>),
              endpoints: Array.from({ length: MAX_ENDPOINTS_PER_ROUTE + 1 }, (_, index) => ({
                ...(endpoint as NonNullable<typeof endpoint>),
                id: `bypassed-${index}`,
              })),
            },
          ],
        },
      ],
    });

    // Act
    const response = await harness.adapter.handle(request('/t/acme/stripe/paid', 'evt-bypassed-cardinality'));

    // Assert
    should(response.status).equal(503);
    should(harness.verificationUrls).have.length(0);
    should(harness.store.events.size).equal(0);
    should(
      harness.telemetry.events.some(
        event => event.name === 'intake.unavailable' && event.attributes.operation === 'config-bounds',
      ),
    ).be.true();
  });

  it('should keep jobs ineligible until the adapter commits a retryable provider acknowledgement', async () => {
    // Arrange
    const harness = await createHarness();
    harness.store.failNext('acknowledge-event', 'acknowledgement transition unavailable');

    // Act
    const unavailable = await harness.adapter.handle(request('/t/acme/stripe/paid', 'evt-ack-gate'));
    const event = [...harness.store.events.values()][0];
    const premature = await (
      await harness.store.claimDueJobs({
        claimToken: 'replica-before-ack',
        leaseMs: 1_000,
        limit: 10,
        nowMs: harness.clock.nowMs(),
      })
    ).unwrap();
    const retry = await harness.adapter.handle(request('/t/acme/stripe/paid', 'evt-ack-gate'));
    const eligible = await (
      await harness.store.claimDueJobs({
        claimToken: 'replica-after-ack',
        leaseMs: 1_000,
        limit: 10,
        nowMs: harness.clock.nowMs(),
      })
    ).unwrap();

    // Assert
    should(unavailable.status).equal(503);
    should(event?.acknowledgedAtMs).be.undefined();
    should(premature).have.length(0);
    should(retry.status).equal(200);
    should(harness.store.events.size).equal(1);
    should((await (await harness.store.getEvent(event?.id ?? '')).unwrap())?.acknowledgedAtMs).equal(
      harness.clock.nowMs(),
    );
    should(eligible).have.length(3);
  });

  it('should commit the raw envelope and every endpoint obligation before acknowledging 200', async () => {
    // Arrange
    const harness = await createHarness();
    const body = '{"type":"invoice.paid","value":42}';

    // Act
    const response = await harness.adapter.handle(request('/t/acme/stripe/paid', 'evt-cardinality', body));
    harness.durableOrder.push('response');
    const event = [...harness.store.events.values()][0];
    const jobs = event === undefined ? [] : await (await harness.store.listEventJobs(event.id)).unwrap();

    // Assert
    should(response.status).equal(200);
    should(harness.durableOrder[0]?.startsWith('durable:')).be.true();
    should(harness.durableOrder[1]).equal('response');
    should(event).not.be.undefined();
    should(decoder.decode(event?.rawBody)).equal(body);
    should(event?.headers['content-type']).equal('application/json');
    should(event?.headers['x-provider-signature']).be.undefined();
    should(event?.providerSequence).equal('provider-sequence-7');
    should(event?.obligations).have.length(3);
    should(jobs).have.length(3);
    should(event?.obligations.map(obligation => obligation.endpointId)).deepEqual(['local', 'remote', 'customer']);
    should(event?.obligations.map(obligation => obligation.addressKind)).deepEqual(['local', 'canonical', 'external']);
  });

  it('should atomically deduplicate per tenant and route for 72 hours but not across landscapes', async () => {
    // Arrange
    const harness = await createHarness('raichu');
    const otherLandscape = await createHarness('ampharos');
    const duplicateRequests = [
      harness.adapter.handle(request('/t/acme/stripe/paid', 'evt-shared')),
      harness.adapter.handle(request('/t/acme/stripe/paid', 'evt-shared')),
    ];

    // Act
    const concurrent = await Promise.all(duplicateRequests);
    const sameRouteDuplicate = await harness.adapter.handle(request('/t/acme/stripe/paid', 'evt-shared'));
    const otherRoute = await harness.adapter.handle(request('/t/acme/stripe/refunded', 'evt-shared'));
    const otherTenant = await harness.adapter.handle(request('/t/other/stripe/paid', 'evt-shared'));
    const remoteLanding = await otherLandscape.adapter.handle(request('/t/acme/stripe/paid', 'evt-shared'));
    const firstExpiry = [...harness.store.dedupExpiries.values()][0] ?? 0;
    harness.clock.advance(DEDUP_WINDOW_SECONDS * 1_000 + 1);
    const afterExpiry = await harness.adapter.handle(request('/t/acme/stripe/paid', 'evt-shared'));

    // Assert
    should(concurrent.map(response => response.status)).deepEqual([200, 200]);
    should(sameRouteDuplicate.status).equal(200);
    should(otherRoute.status).equal(200);
    should(otherTenant.status).equal(200);
    should(remoteLanding.status).equal(200);
    should(afterExpiry.status).equal(200);
    should(firstExpiry - Date.UTC(2026, 0, 10)).equal(72 * 60 * 60 * 1_000);
    should(harness.store.events.size).equal(4);
    should(otherLandscape.store.events.size).equal(1);
  });

  it('should fallback-deduplicate on body plus signature when no native id exists', async () => {
    // Arrange
    const harness = await createHarness();

    // Act
    await harness.adapter.handle(request('/t/acme/stripe/paid', undefined, '{"same":true}'));
    await harness.adapter.handle(request('/t/acme/stripe/paid', undefined, '{"same":true}'));
    await harness.adapter.handle(request('/t/acme/stripe/paid', undefined, '{"same":false}'));

    // Assert
    should(harness.store.events.size).equal(2);
  });

  it('should honor OrphanedProvider grace then reject the expired path', async () => {
    // Arrange
    const harness = await createHarness();
    harness.source.snapshot = {
      ...harness.source.snapshot,
      revision: 'intake-2',
      tenants: harness.source.snapshot.tenants.map(tenant =>
        tenant.id === 'external/acme' ? { ...tenant, routes: [] } : tenant,
      ),
    };
    await (await harness.compiler.compile()).unwrap();

    // Act
    const duringGrace = await harness.adapter.handle(request('/t/acme/stripe/paid', 'evt-orphan'));
    const orphan = [...harness.store.events.values()][0];
    harness.clock.advance(DEDUP_WINDOW_SECONDS * 1_000 + 1);
    const afterGrace = await harness.adapter.handle(request('/t/acme/stripe/paid', 'evt-expired'));

    // Assert
    should(duringGrace.status).equal(200);
    should(orphan?.obligations).have.length(0);
    should(afterGrace.status).equal(404);
  });

  it('should ignore Host and proxy-host attacks on canonical tenant paths', async () => {
    // Arrange
    const harness = await createHarness();

    // Act
    const canonical = await harness.adapter.handle(
      request('/t/acme/stripe/paid', 'evt-name-blind', '{}', 'valid', 'hooks.other.example'),
    );
    const event = [...harness.store.events.values()][0];

    // Assert
    should(canonical.status).equal(200);
    should(event?.tenantId).equal('external/acme');
    should(harness.verificationUrls).deepEqual(['https://hooks.acme.example/stripe/paid']);
    should(harness.source.reads).equal(1);
  });
});
