import { describe, it } from 'bun:test';
import should from 'should';
import { parseBuildTimeEnv } from '../../src/lib/build-env';

// The build-time tier is injected by the bundler, so the running process cannot
// fix a malformed payload. Every bad shape must degrade to NO build tier rather
// than take the boot down.

describe('parseBuildTimeEnv', () => {
  it('should read a well-formed payload as the build tier', () => {
    // Arrange
    const injected = JSON.stringify({ ATOMI_BRANDING__SHORTNAME: 'FromBuild', ATOMI_FARO__ENABLED: 'true' });

    // Act
    const actual = parseBuildTimeEnv(injected);

    // Assert
    should(actual).deepEqual({ ATOMI_BRANDING__SHORTNAME: 'FromBuild', ATOMI_FARO__ENABLED: 'true' });
  });

  it.each([
    { label: 'the variable is absent entirely', injected: undefined },
    { label: 'the variable is empty (unbundled dev server)', injected: '' },
    { label: 'the payload is unparseable', injected: '{not json' },
    { label: 'the payload is valid JSON but not an object', injected: '"a string"' },
    { label: 'the payload is a bare number', injected: '42' },
    { label: 'the payload is an explicit null', injected: 'null' },
  ])('should degrade to no build tier when $label', ({ injected }) => {
    // Act
    const actual = parseBuildTimeEnv(injected);

    // Assert — empty, never a throw and never a partial record.
    should(actual).deepEqual({});
  });

  it('should pass an array through as the object JSON says it is', () => {
    // Arrange — an array IS an object; the config loader treats its indices as
    // keys and finds no ATOMI_ prefix, so it contributes nothing either way.
    const injected = '["a","b"]';

    // Act
    const actual = parseBuildTimeEnv(injected);

    // Assert
    should(Object.values(actual)).deepEqual(['a', 'b']);
  });
});
