import { describe, expect, test } from 'bun:test';
import catalog from '../features.json';

const expected = new Map([
  ['bun-lib-pack-content', 'gate'],
  ['bun-lib-publint', 'gate'],
  ['bun-lib-attw', 'gate'],
  ['bun-lib-publish-version-guard', 'gate'],
  ['bun-lib-publish-tag-policy', 'gate'],
  ['bun-lib-publish-credential-policy', 'gate'],
  ['bun-lib-publish-command-policy', 'gate'],
  ['bun-lib-package-metadata', 'gate'],
  ['bun-lib-package-workflow-wiring', 'gate'],
  ['bun-lib-publish-workflow-wiring', 'gate'],
  ['bun-lib-dual-build', 'smoke'],
  ['bun-lib-readme-tokenization', 'smoke'],
  ['bun-lib-package-pack', 'smoke'],
  ['bun-lib-usage-skill', 'presence'],
] as const);

describe('bun-lib template probe catalog', () => {
  test('declares the exact host-provable mechanism set and classes', () => {
    const actual = catalog
      .filter(feature => feature.template === 'diene/bun-lib')
      .map(feature => [feature.name, feature.class] as const);

    expect(new Map(actual)).toEqual(expected);
    expect(actual).toHaveLength(expected.size);
  });

  for (const [name, evidenceClass] of expected) {
    test(`${name} has the ${evidenceClass} obligation shape`, async () => {
      const definition = (await import(`../${name}.ts`)).default;
      expect(definition.contractVersion).toBe(1);
      expect(definition.probes.filter(probe => probe.kind === 'baseline')).toHaveLength(1);
      expect(definition.probes.filter(probe => probe.kind === 'mutation')).toHaveLength(
        evidenceClass === 'gate' ? 1 : 0,
      );
    });
  }
});
