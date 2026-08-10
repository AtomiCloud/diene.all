import { describe, it } from 'bun:test';
import should from 'should';
import { BASE_LANDSCAPE, LandscapeResolutionError, resolveLandscape } from '../../src/lib/landscape.js';

describe('resolveLandscape', () => {
  it('should prefer an explicit landscape from the host', () => {
    // Arrange
    const base = { app: { landscape: 'pichu' } };

    // Act
    const actual = resolveLandscape('raichu', base);

    // Assert
    should(actual).equal('raichu');
  });

  it('should fall back to the service-tree app.landscape when none is explicit', () => {
    // Arrange
    const base = { app: { landscape: 'pikachu' } };

    // Act
    const actual = resolveLandscape(undefined, base);

    // Assert
    should(actual).equal('pikachu');
  });

  it('should default to base when neither is present', () => {
    // Arrange
    const base = {};

    // Act
    const actual = resolveLandscape(undefined, base);

    // Assert
    should(actual).equal(BASE_LANDSCAPE);
  });

  it('should treat an explicit "base" and a blank string as base', () => {
    // Arrange / Act / Assert
    should(resolveLandscape('base', {})).equal(BASE_LANDSCAPE);
    should(resolveLandscape('   ', {})).equal(BASE_LANDSCAPE);
  });

  it('should ignore a non-string app.landscape', () => {
    // Arrange
    const base = { app: { landscape: 42 } };

    // Act
    const actual = resolveLandscape(undefined, base);

    // Assert
    should(actual).equal(BASE_LANDSCAPE);
  });

  it('should throw LandscapeResolutionError on an unsafe landscape token', () => {
    // Arrange

    // Act
    const actual = () => resolveLandscape('../etc/passwd', {});

    // Assert
    should(actual).throw(LandscapeResolutionError);
  });
});
