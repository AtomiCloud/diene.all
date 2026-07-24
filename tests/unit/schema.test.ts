import { describe, it } from 'bun:test';
import 'should';
import {
  defaultOtelBlock,
  durationToMilliseconds,
  isOtlpHttpEndpoint,
  otelBlockSchema,
  otelOtlpExporterSchema,
  otelSamplerSchema,
  wireDurationSchema,
} from '../../src/lib/schema';
import { acceptCases, canonicalOtelBlock, rejectCases } from './fixtures/otel-block';

// The OTel config block schema is the engine-owned contract. There is no shared
// C0 otel fixture release, so the accept/reject corpus is transcribed from the
// frozen `goals/c0-contracts.md` §4 block (see tests/unit/fixtures/otel-block.ts).

describe('otelBlockSchema', () => {
  it.each([...acceptCases])('should accept $name', ({ block }) => {
    // Act
    const actual = otelBlockSchema.safeParse(block);

    // Assert
    actual.success.should.be.true();
  });

  it.each([...rejectCases])('should reject $name ($violates)', ({ block }) => {
    // Act
    const actual = otelBlockSchema.safeParse(block);

    // Assert
    actual.success.should.be.false();
  });

  it('should freeze the parsed block into the canonical default shape', () => {
    // Arrange - the frozen canonical block verbatim
    const input = canonicalOtelBlock;

    // Act
    const parsed = otelBlockSchema.parse(input);

    // Assert - signals and their frozen defaults survive parsing
    parsed.logs.enabled.should.be.true();
    parsed.metrics.interval.should.eql('PT60S');
    parsed.traces.sampler.should.eql({ type: 'parentbased_traceidratio', ratio: 1 });
    parsed.traces.exporter.otlp.protocol.should.eql('http/protobuf');
  });

  it('should accept the exported defaultOtelBlock', () => {
    // Act
    const actual = otelBlockSchema.safeParse(defaultOtelBlock);

    // Assert
    actual.success.should.be.true();
  });
});

describe('durationToMilliseconds', () => {
  it.each([
    ['PT10S', 10_000],
    ['PT60S', 60_000],
    ['PT1M', 60_000],
    ['PT0.5S', 500],
  ])('should convert %s to %d milliseconds', (input, expected) => {
    // Act
    const actual = durationToMilliseconds(input);

    // Assert
    actual.should.eql(expected);
  });

  it.each([
    ['a zero duration', 'PT0S'],
    ['a non-ISO string', '10s'],
    ['a negative duration', '-PT1S'],
  ])('should throw a RangeError on %s', (_label, input) => {
    // Act / Assert
    (() => durationToMilliseconds(input)).should.throw(RangeError);
  });
});

describe('isOtlpHttpEndpoint', () => {
  it.each([
    ['http on 4318', 'http://otel-collector:4318', true],
    ['https on 4318', 'https://otel-collector:4318', true],
    ['http on the wrong port', 'http://otel-collector:4317', false],
    ['no explicit port', 'http://otel-collector', false],
    ['non-http scheme', 'ftp://otel-collector:4318', false],
    ['a non-URL string', 'not a url', false],
    ['an empty string', '', false],
  ])('should classify %s', (_label, input, expected) => {
    // Act
    const actual = isOtlpHttpEndpoint(input);

    // Assert
    actual.should.eql(expected);
  });
});

describe('wireDurationSchema', () => {
  it('should accept a canonical ISO-8601 duration', () => {
    // Act
    const actual = wireDurationSchema.safeParse('PT30S');

    // Assert
    actual.success.should.be.true();
  });

  it('should reject a non-canonical duration string', () => {
    // Act
    const actual = wireDurationSchema.safeParse('30 seconds');

    // Assert
    actual.success.should.be.false();
  });
});

describe('otelSamplerSchema', () => {
  it('should reject an out-of-range ratio', () => {
    // Act
    const actual = otelSamplerSchema.safeParse({ type: 'always_on', ratio: 2 });

    // Assert
    actual.success.should.be.false();
  });
});

describe('otelOtlpExporterSchema', () => {
  it('should accept a disabled exporter with an empty endpoint', () => {
    // Act
    const actual = otelOtlpExporterSchema.safeParse({
      enabled: false,
      endpoint: '',
      protocol: 'http/protobuf',
      headers: {},
      timeout: 'PT10S',
    });

    // Assert
    actual.success.should.be.true();
  });
});
