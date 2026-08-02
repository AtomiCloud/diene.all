import { expectGreen, expectRedWithDiagnostic } from './lib/helpers.ts';
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
      async run(repo: any) {
        await plantWhiteBoxTest(repo);
        await expectRedWithDiagnostic(repo, gate, 'hook-go-black-box', /white-box test package .* is forbidden/);
      },
    },
  ],
};
