import { defineSmoke } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

const consumePublishedPackages =
  'version=$(xmlstarlet sel -t -v "/Project/PropertyGroup/Version" Version.props) && consumer=$(mktemp -d) && dotnet new console -o "$consumer" && dotnet add "$consumer" package AtomiCloud.Diene.CoreUtils --version "$version" --source https://api.nuget.org/v3/index.json && dotnet build "$consumer" -c Release; rc=$?; if [ -n "${consumer:-}" ]; then rm -rf "$consumer"; fi; exit "$rc"';

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-lib-publish-roundtrip-green',
    description: 'A clean consumer restores and builds with the published package from nuget.org.',
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
