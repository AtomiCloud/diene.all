// Canonical OTel config block fixtures.
//
// No committed C0 OTel fixture release exists: the shared `contracts/c0`
// release covers only the `config` and `problem` domains, so there is no shared
// otel case file to consume. Every case below is transcribed directly from the
// frozen block in `goals/c0-contracts.md` §4 ("Otel — one canonical block"),
// the normative shape for the whole lib/{bun,dotnet,go}/otel family until C0
// ships an otel case file. Test names cite this provenance so the de-facto
// ownership of these fixtures is unambiguous in review.

type Json = Readonly<Record<string, unknown>>;

interface AcceptCase {
  readonly name: string;
  readonly block: Json;
}

interface RejectCase {
  readonly name: string;
  // The frozen invariant each malformed block violates.
  readonly violates: string;
  readonly block: Json;
}

// The two OTLP endpoints used across the corpus: the frozen fleet-wide port is
// 4318 (R17, http/protobuf); anything else is rejected by the schema.
const VALID_OTLP_ENDPOINT = 'http://otel-collector:4318';
const WRONG_PORT_ENDPOINT = 'http://otel-collector:4317';

function disabledExporter(): Json {
  return {
    console: { enabled: false },
    otlp: { enabled: false, endpoint: '', protocol: 'http/protobuf', headers: {}, timeout: 'PT10S' },
  };
}

function consoleExporter(): Json {
  return {
    console: { enabled: true },
    otlp: { enabled: false, endpoint: '', protocol: 'http/protobuf', headers: {}, timeout: 'PT10S' },
  };
}

function otlpExporter(endpoint: string, headers: Readonly<Record<string, string>> = {}, timeout = 'PT10S'): Json {
  return {
    console: { enabled: false },
    otlp: { enabled: true, endpoint, protocol: 'http/protobuf', headers, timeout },
  };
}

// The verbatim frozen block: every signal enabled, every exporter off,
// parentbased_traceidratio at ratio 1.0, ISO-8601 durations.
const canonicalOtelBlock: Json = {
  logs: { enabled: true, exporter: disabledExporter() },
  metrics: { enabled: true, exporter: disabledExporter(), interval: 'PT60S' },
  traces: {
    enabled: true,
    sampler: { type: 'parentbased_traceidratio', ratio: 1.0 },
    exporter: disabledExporter(),
  },
};

const acceptCases: readonly AcceptCase[] = [
  {
    name: 'the frozen canonical block verbatim (all signals on, all exporters off)',
    block: canonicalOtelBlock,
  },
  {
    name: 'OTLP enabled on every signal with a port-4318 endpoint',
    block: {
      logs: { enabled: true, exporter: otlpExporter(VALID_OTLP_ENDPOINT) },
      metrics: { enabled: true, exporter: otlpExporter(VALID_OTLP_ENDPOINT), interval: 'PT60S' },
      traces: {
        enabled: true,
        sampler: { type: 'parentbased_traceidratio', ratio: 0.25 },
        exporter: otlpExporter(VALID_OTLP_ENDPOINT),
      },
    },
  },
  {
    name: 'console exporters enabled on every signal',
    block: {
      logs: { enabled: true, exporter: consoleExporter() },
      metrics: { enabled: true, exporter: consoleExporter(), interval: 'PT30S' },
      traces: {
        enabled: true,
        sampler: { type: 'always_on', ratio: 1 },
        exporter: consoleExporter(),
      },
    },
  },
  {
    name: 'always_on sampler',
    block: {
      ...canonicalOtelBlock,
      traces: {
        enabled: true,
        sampler: { type: 'always_on', ratio: 1 },
        exporter: disabledExporter(),
      },
    },
  },
  {
    name: 'always_off sampler',
    block: {
      ...canonicalOtelBlock,
      traces: {
        enabled: false,
        sampler: { type: 'always_off', ratio: 0 },
        exporter: disabledExporter(),
      },
    },
  },
  {
    name: 'sampler ratio at the inclusive lower bound 0',
    block: {
      ...canonicalOtelBlock,
      traces: {
        enabled: true,
        sampler: { type: 'parentbased_traceidratio', ratio: 0 },
        exporter: disabledExporter(),
      },
    },
  },
  {
    name: 'sampler ratio at the inclusive upper bound 1',
    block: {
      ...canonicalOtelBlock,
      traces: {
        enabled: true,
        sampler: { type: 'parentbased_traceidratio', ratio: 1 },
        exporter: disabledExporter(),
      },
    },
  },
  {
    name: 'custom OTLP headers and non-default ISO-8601 timeouts and interval',
    block: {
      logs: { enabled: true, exporter: otlpExporter(VALID_OTLP_ENDPOINT, { 'x-api-key': 'secret' }, 'PT5S') },
      metrics: {
        enabled: true,
        exporter: otlpExporter(VALID_OTLP_ENDPOINT, { authorization: 'Bearer t' }, 'PT30S'),
        interval: 'PT15S',
      },
      traces: {
        enabled: true,
        sampler: { type: 'parentbased_traceidratio', ratio: 0.5 },
        exporter: otlpExporter(VALID_OTLP_ENDPOINT, {}, 'PT45S'),
      },
    },
  },
];

const rejectCases: readonly RejectCase[] = [
  {
    name: 'signal key misnamed logging instead of logs',
    violates: 'signal keys are exactly logs/metrics/traces (strict object)',
    block: {
      logging: { enabled: true, exporter: disabledExporter() },
      metrics: { enabled: true, exporter: disabledExporter(), interval: 'PT60S' },
      traces: {
        enabled: true,
        sampler: { type: 'parentbased_traceidratio', ratio: 1 },
        exporter: disabledExporter(),
      },
    },
  },
  {
    name: 'signal key miscased Logs instead of logs',
    violates: 'signal keys are case-sensitive',
    block: {
      Logs: { enabled: true, exporter: disabledExporter() },
      metrics: { enabled: true, exporter: disabledExporter(), interval: 'PT60S' },
      traces: {
        enabled: true,
        sampler: { type: 'parentbased_traceidratio', ratio: 1 },
        exporter: disabledExporter(),
      },
    },
  },
  {
    name: 'exporter expressed as an enum string rather than the per-exporter object',
    violates: 'exporter selection is independent enabled booleans, not a use/exporterType enum',
    block: {
      logs: { enabled: true, exporter: 'otlp' },
      metrics: { enabled: true, exporter: disabledExporter(), interval: 'PT60S' },
      traces: {
        enabled: true,
        sampler: { type: 'parentbased_traceidratio', ratio: 1 },
        exporter: disabledExporter(),
      },
    },
  },
  {
    name: 'exporter carries an unknown use field',
    violates: 'exporter object is strict (no extra keys)',
    block: {
      logs: {
        enabled: true,
        exporter: {
          use: 'otlp',
          console: { enabled: false },
          otlp: { enabled: false, endpoint: '', protocol: 'http/protobuf', headers: {}, timeout: 'PT10S' },
        },
      },
      metrics: { enabled: true, exporter: disabledExporter(), interval: 'PT60S' },
      traces: {
        enabled: true,
        sampler: { type: 'parentbased_traceidratio', ratio: 1 },
        exporter: disabledExporter(),
      },
    },
  },
  {
    name: 'sampler ratio below the inclusive lower bound',
    violates: 'ratio must be within [0, 1]',
    block: {
      ...canonicalOtelBlock,
      traces: {
        enabled: true,
        sampler: { type: 'parentbased_traceidratio', ratio: -0.1 },
        exporter: disabledExporter(),
      },
    },
  },
  {
    name: 'sampler ratio above the inclusive upper bound',
    violates: 'ratio must be within [0, 1]',
    block: {
      ...canonicalOtelBlock,
      traces: {
        enabled: true,
        sampler: { type: 'parentbased_traceidratio', ratio: 1.1 },
        exporter: disabledExporter(),
      },
    },
  },
  {
    name: 'sampler ratio NaN',
    violates: 'ratio must be finite',
    block: {
      ...canonicalOtelBlock,
      traces: {
        enabled: true,
        sampler: { type: 'parentbased_traceidratio', ratio: Number.NaN },
        exporter: disabledExporter(),
      },
    },
  },
  {
    name: 'unknown sampler type',
    violates: 'sampler type must be one of the three frozen values',
    block: {
      ...canonicalOtelBlock,
      traces: {
        enabled: true,
        sampler: { type: 'traceidratio', ratio: 1 },
        exporter: disabledExporter(),
      },
    },
  },
  {
    name: 'non-ISO-8601 duration for the OTLP timeout',
    violates: 'durations are canonical ISO-8601 strings',
    block: {
      logs: { enabled: true, exporter: otlpExporter(VALID_OTLP_ENDPOINT, {}, '10s') },
      metrics: { enabled: true, exporter: disabledExporter(), interval: 'PT60S' },
      traces: {
        enabled: true,
        sampler: { type: 'parentbased_traceidratio', ratio: 1 },
        exporter: disabledExporter(),
      },
    },
  },
  {
    name: 'zero-length duration for the metrics interval',
    violates: 'durations must be positive and fixed-length',
    block: {
      logs: { enabled: true, exporter: disabledExporter() },
      metrics: { enabled: true, exporter: disabledExporter(), interval: 'PT0S' },
      traces: {
        enabled: true,
        sampler: { type: 'parentbased_traceidratio', ratio: 1 },
        exporter: disabledExporter(),
      },
    },
  },
  {
    name: 'enabled OTLP exporter with an empty endpoint',
    violates: 'an enabled OTLP exporter must carry an endpoint',
    block: {
      logs: { enabled: true, exporter: otlpExporter('') },
      metrics: { enabled: true, exporter: disabledExporter(), interval: 'PT60S' },
      traces: {
        enabled: true,
        sampler: { type: 'parentbased_traceidratio', ratio: 1 },
        exporter: disabledExporter(),
      },
    },
  },
  {
    name: 'OTLP endpoint on the wrong port',
    violates: 'OTLP is HTTP/protobuf on port 4318 fleet-wide',
    block: {
      logs: { enabled: true, exporter: otlpExporter(WRONG_PORT_ENDPOINT) },
      metrics: { enabled: true, exporter: disabledExporter(), interval: 'PT60S' },
      traces: {
        enabled: true,
        sampler: { type: 'parentbased_traceidratio', ratio: 1 },
        exporter: disabledExporter(),
      },
    },
  },
  {
    name: 'disabled OTLP exporter still validates a non-empty endpoint (wrong port)',
    violates: 'endpoint shape is checked whenever present, regardless of enabled',
    block: {
      logs: {
        enabled: true,
        exporter: {
          console: { enabled: false },
          otlp: {
            enabled: false,
            endpoint: WRONG_PORT_ENDPOINT,
            protocol: 'http/protobuf',
            headers: {},
            timeout: 'PT10S',
          },
        },
      },
      metrics: { enabled: true, exporter: disabledExporter(), interval: 'PT60S' },
      traces: {
        enabled: true,
        sampler: { type: 'parentbased_traceidratio', ratio: 1 },
        exporter: disabledExporter(),
      },
    },
  },
  {
    name: 'wrong protocol literal',
    violates: 'OTLP protocol is the http/protobuf literal',
    block: {
      logs: {
        enabled: true,
        exporter: {
          console: { enabled: false },
          otlp: { enabled: false, endpoint: '', protocol: 'grpc', headers: {}, timeout: 'PT10S' },
        },
      },
      metrics: { enabled: true, exporter: disabledExporter(), interval: 'PT60S' },
      traces: {
        enabled: true,
        sampler: { type: 'parentbased_traceidratio', ratio: 1 },
        exporter: disabledExporter(),
      },
    },
  },
  {
    name: 'missing the traces signal entirely',
    violates: 'all three signals are required',
    block: {
      logs: { enabled: true, exporter: disabledExporter() },
      metrics: { enabled: true, exporter: disabledExporter(), interval: 'PT60S' },
    },
  },
];

export type { AcceptCase, RejectCase };
export { acceptCases, canonicalOtelBlock, rejectCases, VALID_OTLP_ENDPOINT, WRONG_PORT_ENDPOINT };
