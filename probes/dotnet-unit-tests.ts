import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-unit-tests-green',
      description: 'The registered unit projects pass through the public task surface.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c pls test:unit', 'dotnet-unit-tests', 600000);
      },
    },
    {
      name: 'mutation-dotnet-unit-tests-caught',
      description: 'Weakening the frozen block-key assertion turns the unit tier red.',
      kind: 'mutation',
      expectedImpact: ['dotnet-unit-coverage', 'dotnet-multi-project-coverage'],
      async run(repo: any) {
        await repo.patch('UnitTest/PresetValidationTests.cs', {
          find: '        PostgresOption.Key.Should().Be("Postgres");',
          replace: '        PostgresOption.Key.Should().NotBe("Postgres");',
        });
        await expectRed(repo, 'nix develop .#ci -c pls test:unit', 'dotnet-unit-tests', 600000);
      },
    },
  ],
};
