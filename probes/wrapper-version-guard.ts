import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-version-guard-green',
    description: 'Chart manifest and release tag match before packaging.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#cd -c ./scripts/validate/helm-wrapper.sh version',
        'wrapper-version-guard',
      );
    },
  },
  mutation: {
    name: 'mutation-wrapper-version-guard-caught',
    description: 'A manifest/tag mismatch is rejected.',
    expectedImpact: [],
    async run(repo: any) {
      const path = 'chart/Chart.yaml';
      const original = await repo.read(path);
      try {
        await repo.patch(path, { find: 'version: 0.1.0', replace: 'version: 0.2.0' });
        await expectRed(
          repo,
          'nix develop .#cd -c ./scripts/validate/helm-wrapper.sh version',
          'wrapper-version-guard',
        );
      } finally {
        await repo.write(path, original);
      }
    },
  },
});
