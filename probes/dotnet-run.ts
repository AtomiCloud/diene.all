import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  feature: 'dotnet-run',
  probes: [
    {
      name: 'baseline-dotnet-run-executes',
      description: 'The development run task executes the sample App.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#default -c pls run | rg -F "Success: infra presets composed, validated, and schema round-tripped"',
          'dotnet-base-probe-run',
        );
      },
    },
  ],
};
