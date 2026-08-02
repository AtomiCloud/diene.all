import { expectGreen, expectRedWithDiagnostic, restoreProbeState } from './lib/helpers.ts';
import { flipGoAssertion } from './lib/go.ts';

const gate = 'nix develop .#ci -c pls test:unit';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-unit-tests-green',
      description: 'Black-box unit tests pass against the public domain surface.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'unit-tests');
      },
    },
    {
      name: 'mutation-unit-tests-caught',
      description: 'Flipping one public-surface assertion must turn the unit tier red.',
      kind: 'mutation',
      async run(repo: any) {
        const mutated = await flipGoAssertion(repo);
        try {
          await expectRedWithDiagnostic(repo, gate, 'unit-tests', /Slug\(\) =/);
        } finally {
          await restoreProbeState(repo, [mutated]);
        }
      },
    },
  ],
};
