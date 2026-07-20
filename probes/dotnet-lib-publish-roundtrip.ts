import { defineSmoke } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-lib-publish-roundtrip-green',
    description: 'The remote proof slot publishes both packages and symbols through the API-key skip-duplicate path.',
    async run(repo: any) {
      await expectGreen(
        repo,
        "GITHUB_REF_NAME=v$(xmlstarlet sel -t -v '/Project/PropertyGroup/Version' Version.props) nix develop .#cd -c ./scripts/ci/publish.sh",
        'dotnet-lib-publish-roundtrip',
        600000,
      );
    },
  },
});
