import { defineSmoke } from './lib/definition.ts';
import { expectGreenOrOffline } from './wrapper-offline.ts';

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-upstream-latest-green',
    description: 'Skopeo resolves real app-template chart and Podinfo image tags.',
    async run(repo: any) {
      await expectGreenOrOffline(
        repo,
        'nix develop .#default -c ./scripts/local/latest-chart-upstreams.sh',
        'wrapper-upstream-latest',
      );
    },
  },
});
