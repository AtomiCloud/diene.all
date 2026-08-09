import { defineSmoke } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-config-vendoring-green',
    description: 'External application YAML is copied into the ignored chart build area and bundled by Files.Glob.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh config-vendoring',
        'wrapper-config-vendoring',
      );
    },
  },
});
