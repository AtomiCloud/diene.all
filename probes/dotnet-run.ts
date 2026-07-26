import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-run-green',
      description: 'The development run task executes the sample App.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#default -c pls run | rg -F "Success: core-utils round trip matched"',
          'dotnet-base-probe-run',
        );
      },
    },
  ],
};
