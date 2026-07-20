import { defineSmoke } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-lib-dual-pack-green',
    description: 'A normal solution pack emits both packages and both symbol packages.',
    async run(repo: any) {
      await expectGreen(repo, 'nix develop .#ci -c ./scripts/ci/pkg-validate.sh', 'dotnet-lib-dual-pack', 600000);
    },
  },
});
