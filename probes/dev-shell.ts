import { expectDevShellsOnce } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dev-shell-green',
      description: 'Every workspace development shell evaluates and starts.',
      kind: 'baseline',
      async run(repo: any) {
        await expectDevShellsOnce(repo);
      },
    },
  ],
};
