import type { TraceEmitter } from '@atomicloud/diene.otel';
import type { Logger } from 'pino';
import { Counter, Gauge, Histogram, type Registry } from 'prom-client';
import type { RuntimeTelemetry, TelemetryEvent } from '../domain/index.ts';

const signalIdentity = {
  module: 'hooks',
  platform: 'mercury',
  service: 'webhook',
} as const;

const stringAttribute = (event: TelemetryEvent, name: string, fallback = 'unknown'): string =>
  String(event.attributes[name] ?? fallback);

const deliveryFailureReason = (event: TelemetryEvent): string => {
  const status = event.attributes.status;
  if (typeof status === 'number' && Number.isFinite(status)) {
    return `${Math.floor(status / 100)}xx`;
  }
  return ['cancelled', 'network', 'timeout', 'unavailable'].includes(String(status)) ? String(status) : 'unknown';
};

const errorEvents = new Set<TelemetryEvent['name']>([
  'archive.failure',
  'config.materialize.failure',
  'config.retention.failure',
  'console.incident',
  'delivery.failure',
  'intake.unavailable',
  'runtime.job.failure',
  'runtime.shutdown.timeout',
  'verification.failure',
]);

/** Stable Prometheus catalog from observability/SIGNALS.md. */
export class MercuryTelemetry implements RuntimeTelemetry {
  readonly intake: Counter<'landscape' | 'outcome' | 'provider'>;
  readonly verificationFailures: Counter<'landscape' | 'provider'>;
  readonly dedupHits: Counter<'landscape' | 'provider'>;
  readonly eventsPersisted: Counter<'landscape' | 'provider'>;
  readonly deliveryAttempts: Counter<'landscape' | 'outcome'>;
  readonly deliveryFailures: Counter<'landscape' | 'reason'>;
  readonly deliveryLag: Histogram<'landscape'>;
  readonly deliveryQueueDepth: Gauge<'landscape'>;
  readonly dlqDepth: Gauge<'landscape'>;
  readonly staleMap: Counter<'landscape'>;
  readonly quotaBreaches: Counter<'landscape'>;
  readonly archiveSuccess: Counter<'landscape'>;
  readonly archiveFailures: Counter<'landscape'>;
  readonly circuitOpen: Gauge<'endpoint' | 'landscape' | 'tenant'>;
  readonly appleBackfillMissedCycles: Gauge<'landscape' | 'operation'>;

  constructor(
    readonly logger: Logger,
    readonly traces: TraceEmitter,
    readonly registry: Registry,
  ) {
    registry.setDefaultLabels(signalIdentity);
    this.intake = new Counter({
      name: 'mercury_intake_total',
      help: 'Registered provider requests by terminal intake outcome.',
      labelNames: ['landscape', 'provider', 'outcome'],
      registers: [registry],
    });
    this.verificationFailures = new Counter({
      name: 'mercury_verification_failures_total',
      help: 'Provider requests rejected before persistence.',
      labelNames: ['landscape', 'provider'],
      registers: [registry],
    });
    this.dedupHits = new Counter({
      name: 'mercury_dedup_hits_total',
      help: 'Landscape-local 72-hour deduplication hits.',
      labelNames: ['landscape', 'provider'],
      registers: [registry],
    });
    this.eventsPersisted = new Counter({
      name: 'mercury_events_persisted_total',
      help: 'Events durably persisted before provider acknowledgement.',
      labelNames: ['landscape', 'provider'],
      registers: [registry],
    });
    this.deliveryAttempts = new Counter({
      name: 'mercury_delivery_attempts_total',
      help: 'Endpoint delivery attempts by outcome.',
      labelNames: ['landscape', 'outcome'],
      registers: [registry],
    });
    this.deliveryFailures = new Counter({
      name: 'mercury_delivery_failures_total',
      help: 'Failed endpoint delivery attempts by bounded reason.',
      labelNames: ['landscape', 'reason'],
      registers: [registry],
    });
    this.deliveryLag = new Histogram({
      name: 'mercury_delivery_lag_seconds',
      help: 'Observed receive-to-success delivery lag.',
      labelNames: ['landscape'],
      buckets: [0.1, 1, 5, 30, 60, 300, 3_600, 21_600],
      registers: [registry],
    });
    this.deliveryQueueDepth = new Gauge({
      name: 'mercury_delivery_queue_depth',
      help: 'Pending and due landscape-local delivery work.',
      labelNames: ['landscape'],
      registers: [registry],
    });
    this.dlqDepth = new Gauge({
      name: 'mercury_dlq_depth',
      help: 'Replayable exhausted delivery obligations.',
      labelNames: ['landscape'],
      registers: [registry],
    });
    this.staleMap = new Counter({
      name: 'mercury_stale_map_total',
      help: 'HTTP 421 responses that trigger the single permitted refresh.',
      labelNames: ['landscape'],
      registers: [registry],
    });
    this.quotaBreaches = new Counter({
      name: 'mercury_quota_breaches_total',
      help: 'In-application webhook intake quota decisions.',
      labelNames: ['landscape'],
      registers: [registry],
    });
    this.archiveSuccess = new Counter({
      name: 'mercury_archive_success_total',
      help: 'Month streams verified in archive storage.',
      labelNames: ['landscape'],
      registers: [registry],
    });
    this.archiveFailures = new Counter({
      name: 'mercury_archive_failures_total',
      help: 'Archive failures that preserve the Redis source data.',
      labelNames: ['landscape'],
      registers: [registry],
    });
    this.circuitOpen = new Gauge({
      name: 'mercury_circuit_open',
      help: 'Endpoint circuit state, where one is open and zero is closed.',
      labelNames: ['landscape', 'tenant', 'endpoint'],
      registers: [registry],
    });
    this.appleBackfillMissedCycles = new Gauge({
      name: 'mercury_apple_backfill_missed_cycles',
      help: 'Consecutive Apple Server API backfill cycles missed by the singleton; reset to zero after a successful cycle.',
      labelNames: ['landscape', 'operation'],
      registers: [registry],
    });
  }

  async record(event: TelemetryEvent): Promise<void> {
    const landscape = stringAttribute(event, 'landscape');
    const provider = stringAttribute(event, 'provider');
    switch (event.name) {
      case 'route.unknown':
        this.intake.inc({ landscape, provider, outcome: 'unknown_route' });
        break;
      case 'verification.failure':
        this.intake.inc({
          landscape,
          provider,
          outcome: 'verification_failed',
        });
        this.verificationFailures.inc({ landscape, provider });
        break;
      case 'quota.exhausted':
        this.intake.inc({ landscape, provider, outcome: 'quota_exhausted' });
        this.quotaBreaches.inc({ landscape });
        break;
      case 'dedup.hit':
        this.intake.inc({ landscape, provider, outcome: 'duplicate' });
        this.dedupHits.inc({ landscape, provider });
        break;
      case 'intake.accepted':
        this.intake.inc({ landscape, provider, outcome: 'accepted' });
        this.eventsPersisted.inc({ landscape, provider });
        break;
      case 'intake.unavailable':
        this.intake.inc({ landscape, provider, outcome: 'unavailable' });
        break;
      case 'delivery.success':
        this.deliveryAttempts.inc({ landscape, outcome: 'success' });
        if (event.value !== undefined) {
          this.deliveryLag.observe({ landscape }, event.value);
        }
        break;
      case 'delivery.failure':
        this.deliveryAttempts.inc({ landscape, outcome: 'failure' });
        this.deliveryFailures.inc({
          landscape,
          reason: deliveryFailureReason(event),
        });
        break;
      case 'delivery.queue.depth':
        this.deliveryQueueDepth.set({ landscape }, Math.max(0, event.value ?? 0));
        break;
      case 'dlq.depth':
        this.dlqDepth.set({ landscape }, Math.max(0, event.value ?? 0));
        break;
      case 'dlq.enqueued':
        this.dlqDepth.inc({ landscape });
        break;
      case 'stale-map':
        this.staleMap.inc({ landscape });
        break;
      case 'archive.success':
        this.archiveSuccess.inc({ landscape });
        break;
      case 'archive.failure':
        this.archiveFailures.inc({ landscape });
        break;
      case 'circuit.opened':
      case 'circuit.closed':
        this.circuitOpen.set(
          {
            endpoint: stringAttribute(event, 'endpoint'),
            landscape,
            tenant: stringAttribute(event, 'tenant'),
          },
          event.name === 'circuit.opened' ? 1 : 0,
        );
        break;
      case 'provider.apple.backfill':
        this.appleBackfillMissedCycles.set(
          { landscape, operation: stringAttribute(event, 'operation') },
          Math.max(0, event.value ?? 0),
        );
        break;
      default:
        break;
    }

    this.logger.info({ ...event.attributes, event: event.name }, 'mercury runtime event');
    await this.traces
      .emit({
        name: `mercury.${event.name}`,
        attributes: event.attributes,
        status: errorEvents.has(event.name) ? 'error' : 'ok',
      })
      .match({
        ok: () => undefined,
        err: error => this.logger.warn({ error, event: event.name }, 'trace emission failed'),
      });
  }
}
