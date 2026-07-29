import { describe, it } from 'bun:test';
import should from 'should';
import { DEDUP_WINDOW_SECONDS, type RegistrationSnapshot } from '../../../src/domain/index.ts';
import {
  boundedJsonDocumentByteLength,
  MAX_CONFIG_DOCUMENT_BYTES,
  MAX_ENDPOINTS_PER_ROUTE,
  MAX_FANOUT_PER_TENANT,
  MAX_ROUTES_PER_TENANT,
} from '../../../src/runtime/config.ts';
import { MercuryConfigCompiler } from '../../../src/runtime/config-compiler.ts';
import { ManualClock, MemorySnapshotSource, MemoryTelemetry } from '../../../src/runtime/fakes.ts';
import { MemoryLandscapeStore } from '../../../src/storage/memory.ts';

const snapshot = (): RegistrationSnapshot => ({
  revision: 'revision-1',
  tenants: [
    {
      id: 'internal/zinc',
      slug: 'zinc',
      registeredDomains: ['hooks.zinc.example'],
      intakeRps: 50,
      intakeBurst: 200,
      retryWindowMs: 72 * 60 * 60 * 1_000,
      routes: [
        {
          id: 'stripe-complete',
          path: '/stripe/complete',
          provider: 'stripe',
          registeredUrl: 'https://hooks.zinc.example/stripe/complete',
          verificationSecretRef: 'verification/stripe',
          endpoints: [
            {
              id: 'local-row',
              targetKind: 'coordinate',
              canonicalUrl: 'https://checkout.zinc.mew.cluster.atomi.cloud/internal/webhooks/stripe',
              localUrls: {
                raichu: 'http://checkout.zinc.svc.cluster.local/internal/webhooks/stripe',
              },
              signingSecretRef: 'delivery/zinc',
            },
            {
              id: 'remote-row',
              targetKind: 'coordinate',
              canonicalUrl: 'https://checkout.zinc.celebi.cluster.atomi.cloud/internal/webhooks/stripe',
              localUrls: {
                ampharos: 'http://checkout.zinc.svc.cluster.local/internal/webhooks/stripe',
              },
              signingSecretRef: 'delivery/zinc',
            },
            {
              id: 'external-target',
              targetKind: 'external',
              canonicalUrl: 'https://customer.example/webhooks/stripe',
              localUrls: {},
              signingSecretRef: 'delivery/customer',
            },
          ],
        },
      ],
    },
  ],
});

describe('MercuryConfigCompiler', () => {
  it('should measure escaped UTF-8 JSON without materializing past the bound', () => {
    // Arrange
    const document = {
      ascii: 'quote" slash\\ control\n',
      unicode: 'mercury-☿-🚀',
      values: [true, false, null, 42],
    };
    const exact = new TextEncoder().encode(JSON.stringify(document)).byteLength;

    // Act
    const measured = boundedJsonDocumentByteLength(document, exact);
    const bounded = boundedJsonDocumentByteLength(document, 10);

    // Assert
    should(measured).equal(exact);
    should(bounded).equal(11);
  });

  it('should preserve registration cardinality while selecting local, canonical, and external addresses', async () => {
    // Arrange
    const clock = new ManualClock(Date.UTC(2026, 0, 1));
    const store = new MemoryLandscapeStore('raichu', clock);
    const source = new MemorySnapshotSource(snapshot());
    const subject = new MercuryConfigCompiler('raichu', source, store, clock, new MemoryTelemetry());

    // Act
    const compiledResult = await subject.compile();
    const actual = await compiledResult.unwrap();
    const endpoints = actual.tenants[0]?.routes[0]?.endpoints ?? [];

    // Assert
    should(endpoints).have.length(3);
    should(endpoints.map(endpoint => endpoint.id)).deepEqual(['local-row', 'remote-row', 'external-target']);
    should(endpoints.map(endpoint => endpoint.addressKind)).deepEqual(['local', 'canonical', 'external']);
    should(endpoints[0]?.address).equal('http://checkout.zinc.svc.cluster.local/internal/webhooks/stripe');
    should(endpoints[1]?.address).equal('https://checkout.zinc.celebi.cluster.atomi.cloud/internal/webhooks/stripe');
  });

  it('should leave readers on the old generation until the pointer is atomically activated', async () => {
    // Arrange
    const clock = new ManualClock(1_000);
    const store = new MemoryLandscapeStore('raichu', clock);
    const source = new MemorySnapshotSource(snapshot());
    const subject = new MercuryConfigCompiler('raichu', source, store, clock, new MemoryTelemetry());
    const first = await (await subject.compile()).unwrap();
    const staged = { ...first, generation: 2, sourceRevision: 'revision-2' };

    // Act
    await (await store.stage(staged)).unwrap();
    const beforeSwap = await (await store.readActive()).unwrap();
    await (await store.activate(2, 1)).unwrap();
    const afterSwap = await (await store.readActive()).unwrap();

    // Assert
    should(beforeSwap?.generation).equal(1);
    should(beforeSwap?.sourceRevision).equal('revision-1');
    should(afterSwap?.generation).equal(2);
    should(afterSwap?.sourceRevision).equal('revision-2');
  });

  it('should retain the previous generation through grace and never discard the active generation', async () => {
    // Arrange
    const clock = new ManualClock(1_000);
    const store = new MemoryLandscapeStore('raichu', clock);
    const source = new MemorySnapshotSource(snapshot());
    const subject = new MercuryConfigCompiler('raichu', source, store, clock, new MemoryTelemetry(), 500);
    const first = await (await subject.compile()).unwrap();
    source.snapshot = { ...source.snapshot, revision: 'revision-2' };

    // Act
    const second = await (await subject.compile()).unwrap();
    const retainedPrevious = await store.retainGeneration(first.generation, 1_500);
    const retainedActive = await store.retainGeneration(second.generation, 1_500);
    const beforeDeadline = await (await store.discardExpired(1_499)).unwrap();
    const activeDiscard = await store.discard(second.generation);
    const atDeadline = await (await store.discardExpired(1_500)).unwrap();

    // Assert
    should(first.generation).equal(1);
    should(second.generation).equal(2);
    should(await retainedPrevious.isOk()).be.true();
    should(await retainedActive.isErr()).be.true();
    should((await retainedActive.unwrapErr()).code).equal('conflict');
    should(beforeDeadline).deepEqual([]);
    should(await activeDiscard.isErr()).be.true();
    should((await activeDiscard.unwrapErr()).code).equal('conflict');
    should(atDeadline).deepEqual([1]);
    should(store.configGenerations.has(1)).be.false();
    should(store.configGenerations.has(2)).be.true();
    should((await (await store.readActive()).unwrap())?.generation).equal(2);
  });

  it('should retain verification and persistence without endpoints during OrphanedProvider grace', async () => {
    // Arrange
    const clock = new ManualClock(Date.UTC(2026, 0, 1));
    const store = new MemoryLandscapeStore('raichu', clock);
    const source = new MemorySnapshotSource(snapshot());
    const telemetry = new MemoryTelemetry();
    const subject = new MercuryConfigCompiler('raichu', source, store, clock, telemetry);
    await (await subject.compile()).unwrap();
    source.snapshot = {
      ...source.snapshot,
      revision: 'revision-2',
      tenants: source.snapshot.tenants.map(tenant => ({
        ...tenant,
        routes: [],
      })),
    };

    // Act
    const orphaned = await (await subject.compile()).unwrap();
    clock.advance(DEDUP_WINDOW_SECONDS * 1_000 - 1);
    const duringGrace = await (await subject.compile()).unwrap();
    clock.advance(2);
    const afterGrace = await (await subject.compile()).unwrap();

    // Assert
    should(orphaned.tenants[0]?.routes).have.length(1);
    should(orphaned.tenants[0]?.routes[0]?.endpoints).have.length(0);
    should(orphaned.tenants[0]?.routes[0]?.orphanedUntilMs).be.a.Number();
    should(duringGrace.tenants[0]?.routes).have.length(1);
    should(afterGrace.tenants[0]?.routes).have.length(0);
    should(telemetry.events.some(event => event.name === 'orphaned-provider')).be.true();
  });

  it('should reject retry windows above the 72-hour product cap without swapping config', async () => {
    // Arrange
    const clock = new ManualClock(1_000);
    const store = new MemoryLandscapeStore('raichu', clock);
    const invalid = snapshot();
    const source = new MemorySnapshotSource({
      ...invalid,
      tenants: invalid.tenants.map(tenant => ({
        ...tenant,
        retryWindowMs: 73 * 60 * 60 * 1_000,
      })),
    });
    const subject = new MercuryConfigCompiler('raichu', source, store, clock, new MemoryTelemetry());

    // Act
    const actual = await subject.compile();
    const active = await (await store.readActive()).unwrap();

    // Assert
    should(await actual.isErr()).be.true();
    should(active).be.null();
  });

  it('should reserve unique generations so concurrent compiles cannot overwrite one another', async () => {
    // Arrange
    const clock = new ManualClock(1_000);
    const store = new MemoryLandscapeStore('raichu', clock);
    const initialSource = new MemorySnapshotSource(snapshot());
    const telemetry = new MemoryTelemetry();
    await (await new MercuryConfigCompiler('raichu', initialSource, store, clock, telemetry).compile()).unwrap();
    const sourceA = new MemorySnapshotSource({
      ...snapshot(),
      revision: 'concurrent-a',
    });
    const sourceB = new MemorySnapshotSource({
      ...snapshot(),
      revision: 'concurrent-b',
    });
    const compilerA = new MercuryConfigCompiler('raichu', sourceA, store, clock, telemetry);
    const compilerB = new MercuryConfigCompiler('raichu', sourceB, store, clock, telemetry);

    // Act
    const results = await Promise.all([compilerA.compile(), compilerB.compile()]);
    const active = await (await store.readActive()).unwrap();

    // Assert
    const successes = await Promise.all(results.map(result => result.isOk()));
    should(successes.filter(Boolean)).have.length(1);
    should(store.lastReservedGeneration).equal(3);
    should(['concurrent-a', 'concurrent-b']).containEql(active?.sourceRevision);
  });

  it('should reject oversized route, endpoint, tenant fan-out, and document cardinality before staging', async () => {
    // Arrange
    const clock = new ManualClock(1_000);
    const invalidEndpointCount = snapshot();
    const endpointTemplate = invalidEndpointCount.tenants[0]?.routes[0]?.endpoints[0];
    should(endpointTemplate).not.be.undefined();
    const invalidFanout = snapshot();
    const routeTemplate = invalidFanout.tenants[0]?.routes[0];
    should(routeTemplate).not.be.undefined();
    const sources = [
      new MemorySnapshotSource({
        ...invalidEndpointCount,
        tenants: invalidEndpointCount.tenants.map(tenant => ({
          ...tenant,
          routes: tenant.routes.map(route => ({
            ...route,
            endpoints: Array.from({ length: MAX_ENDPOINTS_PER_ROUTE + 1 }, (_, index) => ({
              ...(endpointTemplate as NonNullable<typeof endpointTemplate>),
              id: `endpoint-${index}`,
            })),
          })),
        })),
      }),
      new MemorySnapshotSource({
        ...invalidFanout,
        tenants: invalidFanout.tenants.map(tenant => ({
          ...tenant,
          routes: Array.from(
            { length: Math.ceil((MAX_FANOUT_PER_TENANT + 1) / MAX_ENDPOINTS_PER_ROUTE) },
            (_, routeIndex) => ({
              ...(routeTemplate as NonNullable<typeof routeTemplate>),
              id: `route-${routeIndex}`,
              path: `/route-${routeIndex}`,
              endpoints: Array.from(
                {
                  length: Math.min(
                    MAX_ENDPOINTS_PER_ROUTE,
                    MAX_FANOUT_PER_TENANT + 1 - routeIndex * MAX_ENDPOINTS_PER_ROUTE,
                  ),
                },
                (_, endpointIndex) => ({
                  ...(endpointTemplate as NonNullable<typeof endpointTemplate>),
                  id: `endpoint-${routeIndex}-${endpointIndex}`,
                }),
              ),
            }),
          ),
        })),
      }),
      new MemorySnapshotSource({
        ...snapshot(),
        tenants: snapshot().tenants.map(tenant => ({
          ...tenant,
          routes: Array.from({ length: MAX_ROUTES_PER_TENANT + 1 }, (_, routeIndex) => ({
            ...(routeTemplate as NonNullable<typeof routeTemplate>),
            id: `route-${routeIndex}`,
            path: `/route-${routeIndex}`,
            endpoints: [],
          })),
        })),
      }),
      new MemorySnapshotSource({
        ...snapshot(),
        revision: 'x'.repeat(MAX_CONFIG_DOCUMENT_BYTES),
      }),
    ];

    // Act
    const outcomes = await Promise.all(
      sources.map(async source => {
        const store = new MemoryLandscapeStore('raichu', clock);
        const result = await new MercuryConfigCompiler('raichu', source, store, clock, new MemoryTelemetry()).compile();
        return { result, store };
      }),
    );

    // Assert
    for (const outcome of outcomes) {
      should(await outcome.result.isErr()).be.true();
      should(outcome.store.lastReservedGeneration).equal(0);
      should(await (await outcome.store.readActive()).unwrap()).be.null();
    }
  });
});
