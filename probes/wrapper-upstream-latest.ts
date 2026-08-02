import { defineSmoke } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-upstream-latest-green',
    description: 'Skopeo resolves real Podinfo chart and image tags.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#default -c ./scripts/local/latest-chart-upstreams.sh',
        'wrapper-upstream-latest',
      );
    },
  },
});
