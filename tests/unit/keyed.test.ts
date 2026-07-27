import { describe, expect, it } from 'bun:test';
import { z } from 'zod';
import { keyedPreset, named, StandardConfigError, UPPERCASE_KEY } from '../../src/lib/presets/keyed';

describe('UPPERCASE_KEY', () => {
  it('matches UPPERCASE snake names', () => {
    expect(UPPERCASE_KEY.test('MAIN')).toBe(true);
    expect(UPPERCASE_KEY.test('READ_REPLICA_1')).toBe(true);
  });

  it('rejects lowercase, leading-digit, and hyphenated names', () => {
    expect(UPPERCASE_KEY.test('main')).toBe(false);
    expect(UPPERCASE_KEY.test('1MAIN')).toBe(false);
    expect(UPPERCASE_KEY.test('MAIN-1')).toBe(false);
  });
});

describe('keyedPreset', () => {
  const preset = keyedPreset(z.object({ v: z.number() }));

  it('accepts UPPERCASE keys', () => {
    expect(preset.safeParse({ MAIN: { v: 1 } }).success).toBe(true);
  });

  it('rejects lowercase keys', () => {
    expect(preset.safeParse({ main: { v: 1 } }).success).toBe(false);
  });
});

describe('named', () => {
  it('returns the entry for a known key', () => {
    expect(named({ MAIN: 42 }, 'MAIN')).toBe(42);
  });

  it('throws StandardConfigError listing known keys on a miss', () => {
    expect(() => named({ MAIN: 1, REPLICA: 2 }, 'ANALYTICS')).toThrow(StandardConfigError);
    try {
      named({ MAIN: 1, REPLICA: 2 }, 'ANALYTICS');
    } catch (error) {
      expect((error as StandardConfigError).message).toContain('MAIN, REPLICA');
    }
  });

  it('reports (none registered) for an empty block', () => {
    try {
      named({}, 'MAIN');
      throw new Error('expected a throw');
    } catch (error) {
      expect(error).toBeInstanceOf(StandardConfigError);
      expect((error as StandardConfigError).message).toContain('(none registered)');
    }
  });
});
