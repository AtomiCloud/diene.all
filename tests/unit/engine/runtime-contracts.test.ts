import { describe, it } from 'bun:test';
import { inactiveTraceSignal } from '@atomicloud/diene.otel';
import pino from 'pino';
import { Registry } from 'prom-client';
import should from 'should';
import { defaultIntakePortal, IntakeProblemCatalog } from '../../../src/http/intake/problems.ts';
import { MercuryTelemetry } from '../../../src/runtime/telemetry.ts';

const metricNames = [
  'mercury_apple_backfill_missed_cycles',
  'mercury_archive_failures_total',
  'mercury_archive_success_total',
  'mercury_circuit_open',
  'mercury_dedup_hits_total',
  'mercury_delivery_attempts_total',
  'mercury_delivery_failures_total',
  'mercury_delivery_lag_seconds',
  'mercury_delivery_queue_depth',
  'mercury_dlq_depth',
  'mercury_events_persisted_total',
  'mercury_intake_total',
  'mercury_quota_breaches_total',
  'mercury_stale_map_total',
  'mercury_verification_failures_total',
] as const;

describe('runtime public contracts', () => {
  it('should expose the published problem ids, statuses, and portal identity at intake', () => {
    // Arrange
    const runtime = new IntakeProblemCatalog(defaultIntakePortal);

    // Act
    const runtimeProblems = runtime.registry.list();

    // Assert
    should(runtimeProblems.map(problem => problem.id)).deepEqual([
      'compiled_address_stale',
      'persistence_unavailable',
      'quota_exhausted',
      'unknown_route',
      'verification_failed',
    ]);
    for (const problem of runtimeProblems) {
      should(problem.type).startWith('https://problems.atomi.cloud/docs/serving/mercury/webhook/hooks/v1/');
    }
    should(runtime.registry.require('compiled_address_stale').status).equal(421);
    const unavailable = runtime.fromFailure(
      {
        code: 'config-unavailable',
        landscape: 'raichu',
        message: 'configuration unavailable',
      },
      '/t/acme/provider',
    );
    should(unavailable.status).equal(503);
    should(unavailable.type).endWith('/v1/persistence_unavailable');
  });

  it('should register the exact stable metric catalog with constant and bounded labels', async () => {
    // Arrange
    const registry = new Registry();
    const telemetry = new MercuryTelemetry(
      pino({ level: 'silent' }),
      inactiveTraceSignal('mercury.webhook.test', '1').emitter,
      registry,
    );

    // Act
    await telemetry.record({
      name: 'intake.accepted',
      attributes: { landscape: 'raichu', provider: 'stripe', tenant: 'acme' },
    });
    await telemetry.record({
      name: 'delivery.failure',
      attributes: { landscape: 'raichu', status: 503, endpoint: 'receiver' },
    });
    await telemetry.record({
      name: 'delivery.queue.depth',
      attributes: { landscape: 'raichu' },
      value: 7,
    });
    await telemetry.record({
      name: 'dlq.depth',
      attributes: { landscape: 'raichu' },
      value: 2,
    });
    await telemetry.record({
      name: 'console.incident',
      attributes: { landscape: 'raichu', operation: 'render' },
    });
    await telemetry.record({
      name: 'config.materialize.failure',
      attributes: { landscape: 'raichu' },
    });
    await telemetry.record({
      name: 'runtime.shutdown.timeout',
      attributes: { landscape: 'raichu' },
    });
    const registered = (await registry.getMetricsAsJSON()).map(metric => metric.name).sort();
    const exposition = await registry.metrics();

    // Assert
    should(registered).deepEqual([...metricNames].sort());
    should(exposition).containEql('platform="mercury"');
    should(exposition).containEql('service="webhook"');
    should(exposition).containEql('module="hooks"');
    should(exposition).containEql('landscape="raichu"');
    should(exposition).containEql('reason="5xx"');
    should(exposition).not.containEql('mercury_runtime_events_total');
    should(exposition).not.containEql('status="503"');
  });

  it('should publish the bounded Apple backfill missed-cycle gauge and reset it on success', async () => {
    // Arrange
    const registry = new Registry();
    const telemetry = new MercuryTelemetry(
      pino({ level: 'silent' }),
      inactiveTraceSignal('mercury.webhook.test', '1').emitter,
      registry,
    );
    const value = async (): Promise<number | undefined> => {
      const metric = (await registry.getMetricsAsJSON()).find(
        entry => entry.name === 'mercury_apple_backfill_missed_cycles',
      ) as { readonly values?: readonly { readonly labels: Record<string, string>; readonly value: number }[] };
      return metric.values?.find(
        sample => sample.labels.landscape === 'raichu' && sample.labels.operation === 'apple-notification-history',
      )?.value;
    };

    // Act + Assert: escalation past the threshold
    await telemetry.record({
      name: 'provider.apple.backfill',
      attributes: { landscape: 'raichu', operation: 'apple-notification-history', alert: true },
      value: 3,
    });
    should(await value()).equal(3);

    // Act + Assert: a successful cycle resets the durable count to zero
    await telemetry.record({
      name: 'provider.apple.backfill',
      attributes: { landscape: 'raichu', operation: 'apple-notification-history', alert: false },
      value: 0,
    });
    should(await value()).equal(0);
  });
});
