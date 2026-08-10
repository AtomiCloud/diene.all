import { defineSmoke } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-lib-scratch-consumption-green',
    description: 'A scratch .NET 10 project restores and compiles against both package ids.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#ci -c ./scripts/ci/pkg-validate.sh',
        'dotnet-lib-scratch-consumption',
        600000,
      );
    },
  },
});
