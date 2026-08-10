import { parseWireDuration } from '@atomicloud/diene.core-utils';
import { z } from 'zod';

const FIXED_DURATION_ERROR = 'Duration must be a positive, fixed-length canonical ISO 8601 duration';

function durationToMilliseconds(value: string): number {
  const duration = parseWireDuration(value);
  const milliseconds = duration.total({ unit: 'milliseconds' });
  if (!Number.isFinite(milliseconds) || milliseconds <= 0) {
    throw new RangeError(FIXED_DURATION_ERROR);
  }
  return milliseconds;
}

function isOtlpHttpEndpoint(value: string): boolean {
  try {
    const endpoint = new URL(value);
    return (endpoint.protocol === 'http:' || endpoint.protocol === 'https:') && endpoint.port === '4318';
  } catch {
    return false;
  }
}

const wireDurationSchema = z.string().superRefine((value, context) => {
  try {
    durationToMilliseconds(value);
  } catch (error) {
    context.addIssue({
      code: 'custom',
      message: error instanceof Error ? error.message : FIXED_DURATION_ERROR,
    });
  }
});

const otelConsoleExporterSchema = z
  .object({
    enabled: z.boolean(),
  })
  .strict()
  .readonly();

const otelOtlpExporterSchema = z
  .object({
    enabled: z.boolean(),
    endpoint: z.string(),
    protocol: z.literal('http/protobuf'),
    headers: z.record(z.string(), z.string()),
    timeout: wireDurationSchema,
  })
  .strict()
  .superRefine((value, context) => {
    if (value.enabled && value.endpoint.length === 0) {
      context.addIssue({ code: 'custom', message: 'Enabled OTLP exporters require an endpoint', path: ['endpoint'] });
    }
    if (value.endpoint.length > 0 && !isOtlpHttpEndpoint(value.endpoint)) {
      context.addIssue({
        code: 'custom',
        message: 'OTLP endpoint must be an HTTP(S) URL with explicit port 4318',
        path: ['endpoint'],
      });
    }
  })
  .readonly();

const otelExporterSchema = z
  .object({
    console: otelConsoleExporterSchema,
    otlp: otelOtlpExporterSchema,
  })
  .strict()
  .readonly();

const otelLogsSchema = z
  .object({
    enabled: z.boolean(),
    exporter: otelExporterSchema,
  })
  .strict()
  .readonly();

const otelMetricsSchema = z
  .object({
    enabled: z.boolean(),
    exporter: otelExporterSchema,
    interval: wireDurationSchema,
  })
  .strict()
  .readonly();

const otelSamplerSchema = z
  .object({
    type: z.enum(['parentbased_traceidratio', 'always_on', 'always_off']),
    ratio: z.number().finite().min(0).max(1),
  })
  .strict()
  .readonly();

const otelTracesSchema = z
  .object({
    enabled: z.boolean(),
    sampler: otelSamplerSchema,
    exporter: otelExporterSchema,
  })
  .strict()
  .readonly();

const otelBlockSchema = z
  .object({
    logs: otelLogsSchema,
    metrics: otelMetricsSchema,
    traces: otelTracesSchema,
  })
  .strict()
  .readonly();

type OtelConsoleExporter = z.infer<typeof otelConsoleExporterSchema>;
type OtelOtlpExporter = z.infer<typeof otelOtlpExporterSchema>;
type OtelExporter = z.infer<typeof otelExporterSchema>;
type OtelLogs = z.infer<typeof otelLogsSchema>;
type OtelMetrics = z.infer<typeof otelMetricsSchema>;
type OtelSampler = z.infer<typeof otelSamplerSchema>;
type OtelTraces = z.infer<typeof otelTracesSchema>;
type OtelBlock = z.infer<typeof otelBlockSchema>;

const defaultOtelBlock = Object.freeze({
  logs: Object.freeze({
    enabled: true,
    exporter: Object.freeze({
      console: Object.freeze({ enabled: false }),
      otlp: Object.freeze({
        enabled: false,
        endpoint: '',
        headers: Object.freeze({}),
        protocol: 'http/protobuf' as const,
        timeout: 'PT10S',
      }),
    }),
  }),
  metrics: Object.freeze({
    enabled: true,
    exporter: Object.freeze({
      console: Object.freeze({ enabled: false }),
      otlp: Object.freeze({
        enabled: false,
        endpoint: '',
        headers: Object.freeze({}),
        protocol: 'http/protobuf' as const,
        timeout: 'PT10S',
      }),
    }),
    interval: 'PT60S',
  }),
  traces: Object.freeze({
    enabled: true,
    exporter: Object.freeze({
      console: Object.freeze({ enabled: false }),
      otlp: Object.freeze({
        enabled: false,
        endpoint: '',
        headers: Object.freeze({}),
        protocol: 'http/protobuf' as const,
        timeout: 'PT10S',
      }),
    }),
    sampler: Object.freeze({ ratio: 1, type: 'parentbased_traceidratio' as const }),
  }),
}) satisfies OtelBlock;

export type {
  OtelBlock,
  OtelConsoleExporter,
  OtelExporter,
  OtelLogs,
  OtelMetrics,
  OtelOtlpExporter,
  OtelSampler,
  OtelTraces,
};
export {
  defaultOtelBlock,
  durationToMilliseconds,
  isOtlpHttpEndpoint,
  otelBlockSchema,
  otelConsoleExporterSchema,
  otelExporterSchema,
  otelLogsSchema,
  otelMetricsSchema,
  otelOtlpExporterSchema,
  otelSamplerSchema,
  otelTracesSchema,
  wireDurationSchema,
};
