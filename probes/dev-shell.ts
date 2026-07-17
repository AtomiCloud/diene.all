import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dev-shell-green',
      description: 'Every workspace development shell evaluates and starts.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop --no-write-lock-file .#default -c true && nix develop --no-write-lock-file .#ci -c true && nix develop --no-write-lock-file .#cd -c true && nix develop --no-write-lock-file .#releaser -c true',
          'dev-shell',
        );
      },
    },
  ],
};
