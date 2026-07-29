import { describe, expect, test } from 'bun:test';
import { getProviderVerifier, isProviderName, providerNames, providerRegistry } from '../../../src/providers/index.ts';

describe('provider registry', () => {
  test('contains exactly the seven v1 adapters', () => {
    expect(Object.keys(providerRegistry).sort()).toEqual([...providerNames].sort());
    for (const provider of providerNames) {
      expect(getProviderVerifier(provider).provider).toBe(provider);
    }
  });

  test('narrows only registered provider names', () => {
    expect(isProviderName('stripe')).toBeTrue();
    expect(isProviderName('twilio')).toBeFalse();
    expect(isProviderName('cloudflare')).toBeFalse();
  });
});
