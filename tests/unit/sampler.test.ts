import { describe, it } from 'bun:test';
import {
  AlwaysOffSampler,
  AlwaysOnSampler,
  ParentBasedSampler,
  TraceIdRatioBasedSampler,
} from '@opentelemetry/sdk-trace-base';
import 'should';
import type { Environment } from '../../src/lib/environment';
import type { OtelSampler } from '../../src/lib/schema';
import { createTraceSampler } from '../../src/lib/sampler';

const noEnv: Environment = {};

describe('createTraceSampler', () => {
  it('should map parentbased_traceidratio to a ParentBased(TraceIdRatioBased) sampler', () => {
    // Arrange
    const config: OtelSampler = { type: 'parentbased_traceidratio', ratio: 0.25 };

    // Act
    const actual = createTraceSampler(config, noEnv);

    // Assert - Q-I46: the parent-based ratio sampler wraps a ratio root
    (actual instanceof ParentBasedSampler).should.be.true();
  });

  it('should map always_on to an AlwaysOnSampler', () => {
    // Arrange
    const config: OtelSampler = { type: 'always_on', ratio: 1 };

    // Act
    const actual = createTraceSampler(config, noEnv);

    // Assert
    (actual instanceof AlwaysOnSampler).should.be.true();
  });

  it('should map always_off to an AlwaysOffSampler', () => {
    // Arrange
    const config: OtelSampler = { type: 'always_off', ratio: 0 };

    // Act
    const actual = createTraceSampler(config, noEnv);

    // Assert
    (actual instanceof AlwaysOffSampler).should.be.true();
  });

  it.each([
    ['the inclusive lower bound', 0],
    ['the inclusive upper bound', 1],
  ])('should accept a ratio at %s', (_label, ratio) => {
    // Arrange
    const config: OtelSampler = { type: 'parentbased_traceidratio', ratio };

    // Act
    const actual = createTraceSampler(config, noEnv);

    // Assert - a ratio root is still constructed at either bound
    (actual instanceof ParentBasedSampler).should.be.true();
    (new TraceIdRatioBasedSampler(ratio) instanceof TraceIdRatioBasedSampler).should.be.true();
  });

  it('should defer to the SDK by omitting the programmatic sampler when OTEL_TRACES_SAMPLER is set', () => {
    // Arrange - Q-I46: a set OTEL_TRACES_SAMPLER wins; the lib must not clobber it
    const config: OtelSampler = { type: 'always_on', ratio: 1 };
    const environment: Environment = { OTEL_TRACES_SAMPLER: 'traceidratio' };

    // Act
    const actual = createTraceSampler(config, environment);

    // Assert
    (actual === undefined).should.be.true();
  });

  it('should read OTEL_TRACES_SAMPLER from process.env when no environment is supplied', () => {
    // Arrange
    const config: OtelSampler = { type: 'always_on', ratio: 1 };
    const saved = process.env.OTEL_TRACES_SAMPLER;
    delete process.env.OTEL_TRACES_SAMPLER;

    try {
      // Act
      const actual = createTraceSampler(config);

      // Assert - unset env means the programmatic sampler is built
      (actual instanceof AlwaysOnSampler).should.be.true();
    } finally {
      if (saved !== undefined) process.env.OTEL_TRACES_SAMPLER = saved;
    }
  });
});
