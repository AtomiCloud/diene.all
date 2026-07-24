import {
  AlwaysOffSampler,
  AlwaysOnSampler,
  ParentBasedSampler,
  type Sampler,
  TraceIdRatioBasedSampler,
} from '@opentelemetry/sdk-trace-base';
import type { Environment } from './environment.js';
import { hasEnvironmentValue } from './environment.js';
import type { OtelSampler } from './schema.js';

function createTraceSampler(config: OtelSampler, environment: Environment = process.env): Sampler | undefined {
  if (hasEnvironmentValue(environment, 'OTEL_TRACES_SAMPLER')) return undefined;
  switch (config.type) {
    case 'always_on':
      return new AlwaysOnSampler();
    case 'always_off':
      return new AlwaysOffSampler();
    case 'parentbased_traceidratio':
      return new ParentBasedSampler({ root: new TraceIdRatioBasedSampler(config.ratio) });
  }
}

export { createTraceSampler };
