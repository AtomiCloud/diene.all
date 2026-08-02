import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-reloader-green',
    description: 'Workloads receive Reloader by default and an unsafe workload can opt out.',
    async run(repo: any) {
      await expectGreen(repo, 'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh reloader', 'wrapper-reloader');
    },
  },
  mutation: {
    name: 'mutation-wrapper-reloader-caught',
    description: 'Removing the opt-out branch makes reloader conformance red.',
    expectedImpact: [],
    async run(repo: any) {
      await repo.patch('chart/templates/_helpers.tpl', { find: '{{- if .enabled }}', replace: '{{- if true }}' });
      await expectRed(repo, 'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh reloader', 'wrapper-reloader');
    },
  },
});
