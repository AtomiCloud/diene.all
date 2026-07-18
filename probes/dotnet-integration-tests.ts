import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-integration-tests-green',
      description: 'The Redis adapter passes against a real Testcontainers dependency.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c pls test:int', 'dotnet-integration-tests', 600000);
      },
    },
    {
      name: 'mutation-dotnet-integration-tests-caught',
      description: 'Breaking the adapter read path turns the integration tier red.',
      kind: 'mutation',
      expectedImpact: [
        'dotnet-integration-coverage',
        'dotnet-deadcode-all',
        'dotnet-deadcode-production',
        'dotnet-dev',
        'dotnet-run',
        'dotnet-preview',
      ],
      async run(repo: any) {
        await repo.patch('App/Adapters/Redis/RedisNoteRepository.cs', {
          find: '        return data?.ToDomain();',
          replace: '        return null;',
        });
        await expectRed(repo, 'nix develop .#ci -c pls test:int', 'dotnet-integration-tests', 600000);
      },
    },
  ],
};
