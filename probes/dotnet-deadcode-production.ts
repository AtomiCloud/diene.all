import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-deadcode-production-green',
      description: 'The strict production-only dn-inspect pass reports no dead code.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci -c ./scripts/local/dotnet-dead-code.sh --strict-production',
          'dotnet-deadcode-production',
          900000,
        );
      },
    },
    {
      name: 'mutation-dotnet-deadcode-production-caught',
      description: 'An export used only by tests turns the production-only pass red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.write(
          'Lib/TestOnlyExport.cs',
          'namespace AtomiCloud.DotnetBase.Lib;\n\npublic static class TestOnlyExport\n{\n    public static int Value() => 42;\n}\n',
        );
        await repo.write(
          'UnitTest/TestOnlyExport_Value.cs',
          'using AtomiCloud.DotnetBase.Lib;\nusing FluentAssertions;\n\nnamespace AtomiCloud.DotnetBase.UnitTest;\n\npublic class TestOnlyExport_Value\n{\n    [Fact]\n    public void It_should_return_the_fixture_value()\n    {\n        // Arrange\n\n        // Act\n        var actual = TestOnlyExport.Value();\n\n        // Assert\n        actual.Should().Be(42);\n    }\n}\n',
        );
        await expectRed(
          repo,
          'nix develop .#ci -c ./scripts/local/dotnet-dead-code.sh --strict-production',
          'dotnet-deadcode-production',
          900000,
        );
      },
    },
  ],
};
