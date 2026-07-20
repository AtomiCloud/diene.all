import { describe, expect, test } from 'bun:test';
import catalog from '../features.json';

const expected = new Map([
  ['go-lib-module-path', 'gate'],
  ['go-lib-vet', 'gate'],
  ['go-lib-api-compatibility', 'gate'],
  ['go-lib-publish-semver-guard', 'gate'],
  ['go-lib-export-docs', 'gate'],
  ['go-lib-examples', 'gate'],
  ['go-lib-publish-workflow-wiring', 'gate'],
  ['go-lib-meta-tests', 'gate'],
  ['go-lib-meta-coverage', 'gate'],
  ['go-lib-proxy-roundtrip', 'smoke'],
] as const);

describe('go-lib template probe catalog', () => {
  test('declares the exact mechanism set and classes', () => {
    const actual = catalog
      .filter(feature => feature.template === 'diene/go-lib')
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
