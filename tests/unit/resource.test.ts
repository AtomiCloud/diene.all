import { describe, it } from 'bun:test';
import {
  ATTR_DEPLOYMENT_ENVIRONMENT_NAME,
  ATTR_SERVICE_NAME,
  ATTR_SERVICE_NAMESPACE,
  ATTR_SERVICE_VERSION,
} from '@opentelemetry/semantic-conventions';
import 'should';
import type { AppIdentity, OtelEnvironment } from '../../src/lib/resource';
import {
  createOtelResource,
  mapResourceAttributes,
  parseOtelResourceAttributes,
  resourceAttributes,
} from '../../src/lib/resource';

const identity: AppIdentity = {
  landscape: 'lapras',
  platform: 'atomi',
  service: 'diene',
  module: 'otel',
  version: '1.2.3',
};

describe('mapResourceAttributes', () => {
  it('should map the service-tree identity onto semconv and atomi.* attributes', () => {
    // Act
    const actual = mapResourceAttributes(identity);

    // Assert - the R14 fixed mapping
    actual.should.eql({
      [ATTR_DEPLOYMENT_ENVIRONMENT_NAME]: 'lapras',
      [ATTR_SERVICE_NAMESPACE]: 'atomi',
      [ATTR_SERVICE_NAME]: 'diene',
      [ATTR_SERVICE_VERSION]: '1.2.3',
      'atomi.landscape': 'lapras',
      'atomi.module': 'otel',
      'atomi.platform': 'atomi',
      'atomi.service': 'diene',
      'atomi.version': '1.2.3',
    });
  });

  it('should freeze the mapped attributes', () => {
    // Act
    const actual = mapResourceAttributes(identity);

    // Assert
    Object.isFrozen(actual).should.be.true();
  });

  it.each([
    ['a blank landscape', { ...identity, landscape: '' }],
    ['a whitespace service', { ...identity, service: '   ' }],
    ['a missing version', { ...identity, version: '' }],
  ])('should reject %s', (_label, input) => {
    // Act / Assert
    (() => mapResourceAttributes(input as AppIdentity)).should.throw();
  });
});

describe('parseOtelResourceAttributes', () => {
  it.each([
    ['undefined', undefined],
    ['an empty string', ''],
    ['whitespace only', '   '],
  ])('should return an empty record for %s', (_label, input) => {
    // Act
    const actual = parseOtelResourceAttributes(input);

    // Assert
    actual.should.eql({});
    Object.isFrozen(actual).should.be.true();
  });

  it('should parse comma-separated key=value pairs, trimming whitespace', () => {
    // Act
    const actual = parseOtelResourceAttributes(' team = platform , tier=gold ');

    // Assert
    actual.should.eql({ team: 'platform', tier: 'gold' });
  });

  it('should drop malformed entries with no key', () => {
    // Arrange - `novalue` has no separator, `=orphan` has an empty key
    const input = 'team=platform,novalue,=orphan';

    // Act
    const actual = parseOtelResourceAttributes(input);

    // Assert - only the well-formed pair survives
    actual.should.eql({ team: 'platform' });
  });
});

describe('resourceAttributes', () => {
  it('should merge configured attributes with OTEL_RESOURCE_ATTRIBUTES, env winning', () => {
    // Arrange
    const environment: OtelEnvironment = {
      OTEL_RESOURCE_ATTRIBUTES: 'atomi.landscape=prod,custom.key=value',
    };

    // Act
    const actual = resourceAttributes(identity, environment);

    // Assert - the env override replaces the configured atomi.landscape
    actual.should.containEql({
      'atomi.landscape': 'prod',
      'custom.key': 'value',
      [ATTR_SERVICE_NAME]: 'diene',
    });
  });

  it('should let OTEL_SERVICE_NAME override the mapped service name', () => {
    // Arrange
    const environment: OtelEnvironment = { OTEL_SERVICE_NAME: ' checkout ' };

    // Act
    const actual = resourceAttributes(identity, environment);

    // Assert
    actual.should.containEql({ [ATTR_SERVICE_NAME]: 'checkout' });
  });

  it('should keep the configured service name when OTEL_SERVICE_NAME is blank', () => {
    // Arrange
    const environment: OtelEnvironment = { OTEL_SERVICE_NAME: '   ' };

    // Act
    const actual = resourceAttributes(identity, environment);

    // Assert
    actual.should.containEql({ [ATTR_SERVICE_NAME]: 'diene' });
  });

  it('should default to process.env when no environment is supplied', () => {
    // Arrange - isolate the OTEL_* keys this function reads
    const savedAttributes = process.env.OTEL_RESOURCE_ATTRIBUTES;
    const savedService = process.env.OTEL_SERVICE_NAME;
    delete process.env.OTEL_RESOURCE_ATTRIBUTES;
    delete process.env.OTEL_SERVICE_NAME;

    try {
      // Act
      const actual = resourceAttributes(identity);

      // Assert
      actual.should.containEql({ [ATTR_SERVICE_NAME]: 'diene' });
    } finally {
      if (savedAttributes !== undefined) process.env.OTEL_RESOURCE_ATTRIBUTES = savedAttributes;
      if (savedService !== undefined) process.env.OTEL_SERVICE_NAME = savedService;
    }
  });
});

describe('createOtelResource', () => {
  it('should build an SDK resource carrying the mapped attributes', () => {
    // Act
    const resource = createOtelResource(identity, {});

    // Assert
    resource.attributes.should.containEql({ [ATTR_SERVICE_NAME]: 'diene', 'atomi.module': 'otel' });
  });

  it('should default to process.env when no environment is supplied', () => {
    // Arrange
    const savedAttributes = process.env.OTEL_RESOURCE_ATTRIBUTES;
    const savedService = process.env.OTEL_SERVICE_NAME;
    delete process.env.OTEL_RESOURCE_ATTRIBUTES;
    delete process.env.OTEL_SERVICE_NAME;

    try {
      // Act
      const resource = createOtelResource(identity);

      // Assert
      resource.attributes.should.containEql({ [ATTR_SERVICE_NAME]: 'diene' });
    } finally {
      if (savedAttributes !== undefined) process.env.OTEL_RESOURCE_ATTRIBUTES = savedAttributes;
      if (savedService !== undefined) process.env.OTEL_SERVICE_NAME = savedService;
    }
  });
});
