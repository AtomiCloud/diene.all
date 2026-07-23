import { defineSmoke } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

const consumePublishedPackages =
  'version=$(xmlstarlet sel -t -v "/Project/PropertyGroup/Version" Version.props) && rm -rf artifacts/publish-roundtrip && dotnet new console -o artifacts/publish-roundtrip && dotnet add artifacts/publish-roundtrip package AtomiCloud.Diene.Note --version "$version" --source https://api.nuget.org/v3/index.json && dotnet add artifacts/publish-roundtrip package AtomiCloud.Diene.Note.TestHelper --version "$version" --source https://api.nuget.org/v3/index.json && dotnet build artifacts/publish-roundtrip -c Release';

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-lib-publish-roundtrip-green',
    description: 'A clean consumer restores and builds with both published packages from nuget.org.',
    async run(repo: any) {
      await expectGreen(
        repo,
        `nix develop .#cd -c bash -c '${consumePublishedPackages}'`,
        'dotnet-lib-publish-roundtrip',
        600000,
      );
    },
  },
});
