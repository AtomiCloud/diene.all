import { expectGreen, expectRedWithDiagnostic, restoreProbeState } from './lib/helpers.ts';
import { plantWhiteBoxTest } from './lib/go.ts';

const gate = 'nix develop .#ci -c pre-commit run a-go-black-box --all-files';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-go-black-box-hook-green',
      description: 'The generated black-box hook accepts only external Go test packages.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'hook-go-black-box');
      },
    },
    {
      name: 'mutation-go-black-box-hook-caught',
      description: 'A white-box Go test package must turn the owning hook red.',
      kind: 'mutation',
      // The fixture lands beside the first tracked test package, which is the
      // adapter tier, so only rows that build and run that tier can see it.
      expectedImpact: ['integration-tests', 'integration-coverage-scope'],
      async run(repo: any) {
        const planted = await plantWhiteBoxTest(repo);
        try {
          await expectRedWithDiagnostic(repo, gate, 'hook-go-black-box', /white-box test package .* is forbidden/);
        } finally {
          await restoreProbeState(repo, [planted]);
        }
      },
    },
  ],
};
