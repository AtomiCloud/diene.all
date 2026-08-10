import { expectBunGreen } from './lib/bun-command.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-bun-deadcode-review-green',
      description: 'Both lax LLM-review Knip variants run without enforcing false positives.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, 'nix develop .#ci -c task deadcode', 'bun-deadcode-review');
      },
    },
  ],
};
