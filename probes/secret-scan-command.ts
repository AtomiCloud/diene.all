import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-secret-scan-command-green',
      description: 'The public secret-scan task invokes the real scanner.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#default -c task secret:scan', 'secret-scan-command');
      },
    },
  ],
};
