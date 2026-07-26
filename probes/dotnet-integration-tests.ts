import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-integration-tests-green',
      description:
        'The demo consumer satisfies the C0 contract against the host IANA database and the source-owned fixture.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c pls test:int', 'dotnet-integration-tests', 600000);
      },
    },
    {
      name: 'mutation-dotnet-integration-tests-caught',
      description: 'Changing the source-owned C0 instant payload turns the integration tier red.',
      kind: 'mutation',
      expectedImpact: ['dotnet-integration-coverage'],
      async run(repo: any) {
        await repo.patch('fixtures/c0/wire-v1.json', {
          find: '  "instant": "2026-07-25T22:30:00Z",',
          replace: '  "instant": "2026-07-25T23:30:00Z",',
        });
        await expectRed(repo, 'nix develop .#ci -c pls test:int', 'dotnet-integration-tests', 600000);
      },
    },
  ],
};
