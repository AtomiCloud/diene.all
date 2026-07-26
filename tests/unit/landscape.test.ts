import { describe, expect, test } from 'bun:test';
import {
  LandscapeAccessError,
  type LandscapeSource,
  landscape,
  landscapeConfigAnchor,
  SERVING_LANDSCAPE_FIXTURES,
  WORKLOAD_LANDSCAPES,
} from '../../src/lib/landscape';

const sources = ['binding', 'baked-constant', 'dart-define'] as const;
const matrix = [...WORKLOAD_LANDSCAPES, ...SERVING_LANDSCAPE_FIXTURES];

describe('landscape accessor', () => {
  test.each([...sources])('reads every canonical fixture from %s without detection', source => {
    for (const value of matrix) {
      expect(landscape({ source, value })).toBe(value);
    }
  });

  test('trims a supplied source value and anchors config to it', () => {
    expect(landscapeConfigAnchor({ source: 'binding', value: ' lapras ' }, { app: { landscape: 'raichu' } })).toBe(
      'lapras',
    );
  });

  test.each([
    [{ source: 'binding', value: undefined }, 'missing'],
    [{ source: 'baked-constant', value: '   ' }, 'missing'],
    [{ source: 'dart-define', value: 'not/a-landscape' }, 'invalid'],
  ] satisfies readonly [LandscapeSource, LandscapeAccessError['reason']][])(
    'rejects absent or invalid host input %#',
    (input, reason) => {
      try {
        landscape(input);
        throw new Error('expected landscape error');
      } catch (error) {
        expect(error).toBeInstanceOf(LandscapeAccessError);
        expect((error as LandscapeAccessError).source).toBe(input.source);
        expect((error as LandscapeAccessError).value).toBe(input.value);
        expect((error as LandscapeAccessError).reason).toBe(reason);
      }
    },
  );
});

test('the implementation contains no hostname or environment detection surface', async () => {
  const source = await Bun.file(new URL('../../src/lib/landscape/index.ts', import.meta.url)).text();
  expect(source).not.toMatch(/\b(window|location|hostname|process\.env|Bun\.env)\b/);
});
