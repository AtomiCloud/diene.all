import { describe, it } from 'bun:test';
import should from 'should';
import { z } from 'zod';
import { ConfigValidationError, validateConfig } from '../../src/lib/validator.js';

describe('validateConfig', () => {
  it('should return the parsed value when valid', () => {
    // Arrange
    const schema = z.object({ port: z.number() });

    // Act
    const actual = validateConfig(schema, { port: 8080 });

    // Assert
    should(actual).deepEqual({ port: 8080 });
  });

  it('should throw ConfigValidationError with a dotted path for a nested failure', () => {
    // Arrange
    const schema = z.object({ server: z.object({ port: z.number() }) });

    // Act
    const actual = () => validateConfig(schema, { server: { port: 'nope' } });

    // Assert
    should(actual).throw(ConfigValidationError);
    try {
      validateConfig(schema, { server: { port: 'nope' } });
    } catch (error) {
      should(error).be.instanceof(ConfigValidationError);
      should((error as ConfigValidationError).issues[0]).match(/^server\.port: /);
    }
  });

  it('should label a root-level failure as (root)', () => {
    // Arrange
    const schema = z.object({ port: z.number() });

    // Act / Assert
    try {
      validateConfig(schema, 'not-an-object');
      should.fail('expected a throw', 'throw', 'no throw');
    } catch (error) {
      should(error).be.instanceof(ConfigValidationError);
      should((error as ConfigValidationError).issues[0]).match(/^\(root\): /);
    }
  });
});
