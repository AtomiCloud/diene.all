import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-primordial-crs-green',
    description: 'All five primordial helpers validate against the frozen local T3 shape schemas.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh primordial',
        'wrapper-primordial-crs',
      );
    },
  },
  mutation: {
    name: 'mutation-wrapper-primordial-crs-caught',
    description: 'A removed sharing field is rejected by the PlatformDependency schema.',
    expectedImpact: [],
    async run(repo: any) {
      const path = 'chart/templates/primordial-resources.yaml';
      const original = await repo.read(path);
      try {
        await repo.patch(path, {
          find: '  landscape: {{ .Values.primordial.targetLandscape }}\n  placement:',
          replace: '  landscape: {{ .Values.primordial.targetLandscape }}\n  share: true\n  placement:',
        });
        await expectRed(
          repo,
          'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh primordial',
          'wrapper-primordial-crs',
        );
      } finally {
        await repo.write(path, original);
      }
    },
  },
});
