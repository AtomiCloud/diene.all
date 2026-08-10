import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-preview-green',
      description: 'The preview task executes the compiled Release artifact.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#default -c pls preview | rg -F "Success: 42"',
          'dotnet-base-probe-preview',
        );
      },
    },
  ],
};
