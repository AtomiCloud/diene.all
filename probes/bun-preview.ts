import { expectBunGreen } from './lib/bun-command.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-bun-preview-green',
      description: 'The preview task rebuilds and executes the bundled artifact.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(
          repo,
          "nix develop .#ci -c bash -lc './scripts/local/setup.sh && pls preview -- smoke'",
          'bun-preview',
        );
      },
    },
  ],
};
