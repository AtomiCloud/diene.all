import { landscape as landscapeAccessor } from '@atomicloud/diene.frontend-utils/landscape';
import { describe, it } from 'bun:test';
import should from 'should';

// Landscape is READ from the host runtime and NEVER browser-detected: a Worker
// env binding on the OpenNext rail, chart-supplied server runtime config on the
// Garden rail. Both surface as process env, so the mapping table is
// env → accessor output, with `base` as the build-time prerender default.
//
// The accessor is exercised directly here (it is the mechanism); the adapter's
// env-precedence wiring is proven at the int tier
// (tests/integration/server-config.test.ts), which can safely mutate
// process.env around a memoized module.

const read = (env: Record<string, string | undefined>): string =>
  landscapeAccessor({
    source: 'binding',
    value: env['ATOMI_LANDSCAPE'] ?? env['LANDSCAPE'] ?? 'base',
  });

describe('landscape binding', () => {
  it.each([
    { label: 'the ATOMI_ prefixed binding', env: { ATOMI_LANDSCAPE: 'lapras' }, expected: 'lapras' },
    { label: 'the bare binding', env: { LANDSCAPE: 'pichu' }, expected: 'pichu' },
    {
      label: 'both bindings (prefixed wins)',
      env: { ATOMI_LANDSCAPE: 'raichu', LANDSCAPE: 'pichu' },
      expected: 'raichu',
    },
    { label: 'no binding at all (prerender default)', env: {}, expected: 'base' },
  ])('should resolve $label to $expected', ({ env, expected }) => {
    // Act
    const actual = read(env);

    // Assert
    should(actual).equal(expected);
  });

  it.each([{ landscape: 'pichu' }, { landscape: 'pikachu' }, { landscape: 'raichu' }, { landscape: 'lapras' }])(
    'should pass the $landscape binding through unchanged',
    ({ landscape }) => {
      // Assert — no normalisation, no aliasing: the host's name IS the landscape,
      // because the config overlay file is looked up by exactly this string.
      should(read({ ATOMI_LANDSCAPE: landscape })).equal(landscape);
    },
  );

  it('should never detect the landscape from the browser', async () => {
    // Arrange — a hostname-sniffing fallback would make the landscape disagree
    // between server and client render, so the accessor is only ever called with
    // a binding source in this codebase.
    const source = await Bun.file('src/adapters/server-config/index.ts').text();

    // Assert
    should(source).match(/source: 'binding'/);
    should(source).not.match(/window\.|location\.|document\./);
  });
});
