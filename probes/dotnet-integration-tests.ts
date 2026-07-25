import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-integration-tests-green',
      description:
        'The host-backed seam adapters satisfy the shipped contract suites and the source-owned C0 fixture round-trips.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c pls test:int', 'dotnet-integration-tests', 600000);
      },
    },
    {
      name: 'mutation-dotnet-integration-tests-caught',
      description: 'Changing the source-owned C0 duration payload turns the integration tier red.',
      kind: 'mutation',
      expectedImpact: ['dotnet-integration-coverage'],
      async run(repo: any) {
        await repo.patch('fixtures/c0/seam-wire-v1.json', {
          find: '  "duration": "PT1M30S",',
          replace: '  "duration": "PT2M30S",',
        });
        await expectRed(repo, 'nix develop .#ci -c pls test:int', 'dotnet-integration-tests', 600000);
      },
    },
  ],
};
