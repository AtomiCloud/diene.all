import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-hook-dotnet-release-types-green',
      description: 'The generated hook enforces the canonical .NET release vocabulary.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci -c pre-commit run a-dotnet-release-types --all-files',
          'hook-dotnet-release-types',
        );
      },
    },
    {
      name: 'mutation-hook-dotnet-release-types-caught',
      description: 'Removing one releaser type turns the vocabulary hook red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch('release.yaml', {
          find: '  - type: test',
          replace: '  - type: tests',
        });
        await expectRed(
          repo,
          'nix develop .#ci -c pre-commit run a-dotnet-release-types --all-files',
          'hook-dotnet-release-types',
        );
      },
    },
  ],
};
