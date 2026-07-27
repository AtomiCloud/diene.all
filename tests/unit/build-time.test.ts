import { describe, it } from 'bun:test';
import should from 'should';
import { buildTimeValueMap } from '../../src/lib/build-time.js';

describe('buildTimeValueMap', () => {
  it('should keep only prefixed, non-blank variables', () => {
    // Arrange
    const env = {
      ATOMI_CLIENT__FARO__BUILD__KEY: 'secret',
      ATOMI_CLIENT__NAME: 'app',
      ATOMI_BLANK: '',
      OTHER__VAR: 'ignored',
      UNDEFINED_VAR: undefined,
    };

    // Act
    const actual = buildTimeValueMap(env, 'ATOMI_');

    // Assert
    should(actual).deepEqual({
      ATOMI_CLIENT__FARO__BUILD__KEY: 'secret',
      ATOMI_CLIENT__NAME: 'app',
    });
  });

  it('should return an empty map when nothing matches', () => {
    // Arrange
    const env = { PATH: '/usr/bin' };

    // Act
    const actual = buildTimeValueMap(env, 'ATOMI_');

    // Assert
    should(actual).deepEqual({});
  });
});
