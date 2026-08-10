import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  feature: 'dotnet-preview',
  probes: [
    {
      name: 'baseline-dotnet-preview-runs-release-artifact',
      description: 'The preview task executes the compiled Release artifact.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#default -c pls preview | rg -F "Success: infra presets composed, validated, and schema round-tripped"',
          'dotnet-base-probe-preview',
        );
      },
    },
  ],
};
