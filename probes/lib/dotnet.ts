export async function addSecondUnitProject(repo: any, uncovered: boolean): Promise<void> {
  await repo.write(
    'Lib2/Lib2.csproj',
    `<Project Sdk="Microsoft.NET.Sdk">\n  <PropertyGroup>\n    <RootNamespace>AtomiCloud.DotnetBase.Lib2</RootNamespace>\n  </PropertyGroup>\n</Project>\n`,
  );
  await repo.write(
    'Lib2/Calculator.cs',
    `namespace AtomiCloud.DotnetBase.Lib2;\n\npublic class Calculator\n{\n    public int Add(int left, int right) => left + right;\n${
      uncovered ? '\n    public int Subtract(int left, int right) => left - right;\n' : ''
    }}\n`,
  );
  await repo.write(
    'UnitTest2/UnitTest2.csproj',
    `<Project Sdk="Microsoft.NET.Sdk">\n  <PropertyGroup>\n    <RootNamespace>AtomiCloud.DotnetBase.UnitTest2</RootNamespace>\n    <OutputType>Exe</OutputType>\n    <IsPackable>false</IsPackable>\n    <IsTestProject>true</IsTestProject>\n  </PropertyGroup>\n  <ItemGroup>\n    <PackageReference Include="coverlet.msbuild" />\n    <PackageReference Include="FluentAssertions" />\n    <PackageReference Include="GitHubActionsTestLogger" />\n    <PackageReference Include="Microsoft.NET.Test.Sdk" />\n    <PackageReference Include="xunit.v3" />\n    <PackageReference Include="xunit.runner.visualstudio" />\n  </ItemGroup>\n  <ItemGroup>\n    <Using Include="Xunit" />\n  </ItemGroup>\n  <ItemGroup>\n    <ProjectReference Include="../Lib2/Lib2.csproj" />\n  </ItemGroup>\n</Project>\n`,
  );
  await repo.write(
    'UnitTest2/Calculator_Add.cs',
    `using AtomiCloud.DotnetBase.Lib2;\nusing FluentAssertions;\n\nnamespace AtomiCloud.DotnetBase.UnitTest2;\n\npublic class Calculator_Add\n{\n    [Fact]\n    public void It_should_add_two_numbers()\n    {\n        // Arrange\n        var subject = new Calculator();\n\n        // Act\n        var actual = subject.Add(2, 3);\n\n        // Assert\n        actual.Should().Be(5);\n    }\n}\n`,
  );
  await repo.patch('dotnet-base.slnx', {
    find: '  <Project Path="Lib/Lib.csproj" />',
    replace: '  <Project Path="Lib/Lib.csproj" />\n  <Project Path="Lib2/Lib2.csproj" />',
  });
  await repo.patch('dotnet-base.slnx', {
    find: '  <Project Path="UnitTest/UnitTest.csproj" />',
    replace: '  <Project Path="UnitTest/UnitTest.csproj" />\n  <Project Path="UnitTest2/UnitTest2.csproj" />',
  });
  await repo.patch('.config/dotnet-base.test.yaml', {
    find: '      - UnitTest/UnitTest.csproj',
    replace: '      - UnitTest/UnitTest.csproj\n      - UnitTest2/UnitTest2.csproj',
  });
}

// Registers a fully covered project whose assembly name escapes the unit `Lib*` ledger and
// widens the Coverlet include filter to admit it. Both merged packages sit at 100%, so the
// merged line threshold still passes and only the Cobertura package-scope parse can fail.
export async function addEscapingUnitProject(repo: any): Promise<void> {
  await repo.write(
    'Escape/Escape.csproj',
    `<Project Sdk="Microsoft.NET.Sdk">\n  <PropertyGroup>\n    <RootNamespace>AtomiCloud.DotnetBase.Escape</RootNamespace>\n  </PropertyGroup>\n</Project>\n`,
  );
  await repo.write(
    'Escape/Calculator.cs',
    `namespace AtomiCloud.DotnetBase.Escape;\n\npublic class Calculator\n{\n    public int Add(int left, int right) => left + right;\n}\n`,
  );
  await repo.write(
    'EscapeTest/EscapeTest.csproj',
    `<Project Sdk="Microsoft.NET.Sdk">\n  <PropertyGroup>\n    <RootNamespace>AtomiCloud.DotnetBase.EscapeTest</RootNamespace>\n    <OutputType>Exe</OutputType>\n    <IsPackable>false</IsPackable>\n    <IsTestProject>true</IsTestProject>\n  </PropertyGroup>\n  <ItemGroup>\n    <PackageReference Include="coverlet.msbuild" />\n    <PackageReference Include="FluentAssertions" />\n    <PackageReference Include="GitHubActionsTestLogger" />\n    <PackageReference Include="Microsoft.NET.Test.Sdk" />\n    <PackageReference Include="xunit.v3" />\n    <PackageReference Include="xunit.runner.visualstudio" />\n  </ItemGroup>\n  <ItemGroup>\n    <Using Include="Xunit" />\n  </ItemGroup>\n  <ItemGroup>\n    <ProjectReference Include="../Escape/Escape.csproj" />\n  </ItemGroup>\n</Project>\n`,
  );
  await repo.write(
    'EscapeTest/Calculator_Add.cs',
    `using AtomiCloud.DotnetBase.Escape;\nusing FluentAssertions;\n\nnamespace AtomiCloud.DotnetBase.EscapeTest;\n\npublic class Calculator_Add\n{\n    [Fact]\n    public void It_should_add_two_numbers()\n    {\n        // Arrange\n        var subject = new Calculator();\n\n        // Act\n        var actual = subject.Add(2, 3);\n\n        // Assert\n        actual.Should().Be(5);\n    }\n}\n`,
  );
  await repo.patch('dotnet-base.slnx', {
    find: '  <Project Path="App/App.csproj" />',
    replace:
      '  <Project Path="App/App.csproj" />\n  <Project Path="Escape/Escape.csproj" />\n  <Project Path="EscapeTest/EscapeTest.csproj" />',
  });

  const configPath = '.config/dotnet-base.test.yaml';
  const config = await repo.read(configPath);
  const projectAnchor = '      - UnitTest/UnitTest.csproj\n';
  const includeAnchor = "    include:\n      - '[Lib*]*'\n";
  if (!config.includes(projectAnchor) || !config.includes(includeAnchor)) {
    throw new Error(`${configPath} no longer exposes the unit projects/include anchors`);
  }
  await repo.write(
    configPath,
    config
      .replace(projectAnchor, `${projectAnchor}      - EscapeTest/EscapeTest.csproj\n`)
      .replace(includeAnchor, `${includeAnchor}      - '[Escape]*'\n`),
  );
}
