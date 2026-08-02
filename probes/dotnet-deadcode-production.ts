import { expectGreen, expectRed } from './lib/helpers.ts';
import { addSecondUnitProject } from './lib/dotnet.ts';

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
        await addSecondUnitProject(repo, false);
        await repo.write(
          'Lib2/TestOnlyExport.cs',
          'namespace AtomiCloud.DotnetBase.Lib2;\n\npublic static class TestOnlyExport\n{\n    public static int Value() => 42;\n}\n',
        );
        await repo.write(
          'UnitTest2/TestOnlyExport_Value.cs',
          'using AtomiCloud.DotnetBase.Lib2;\nusing FluentAssertions;\n\nnamespace AtomiCloud.DotnetBase.UnitTest2;\n\npublic class TestOnlyExport_Value\n{\n    [Fact]\n    public void It_should_return_the_fixture_value()\n    {\n        // Arrange\n\n        // Act\n        var actual = TestOnlyExport.Value();\n\n        // Assert\n        actual.Should().Be(42);\n    }\n}\n',
        );
        await expectRed(
          repo,
          'nix develop .#ci -c ./scripts/local/dotnet-dead-code.sh --strict-production',
          'dotnet-deadcode-production',
          900000,
          'TestOnlyExport',
        );
      },
    },
  ],
};
