import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

const CHART = 'infra/root_chart';
const GATE = `nix develop .#ci -c helm lint ${CHART}`;

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-api-app-chart-lint-green',
    description: 'helm lint accepts the app chart through its own invocation.',
    async run(repo: any) {
      await expectGreen(repo, GATE, 'dotnet-api-app-chart-lint', 240000);
    },
  },
  mutation: {
    name: 'mutation-dotnet-api-app-chart-lint-caught',
    description: 'Invalidating the app chart metadata turns lint red.',
    async run(repo: any) {
      await repo.patch(`${CHART}/Chart.yaml`, { find: 'apiVersion: v2', replace: 'apiVersion: invalid' });
      await expectRed(repo, GATE, 'dotnet-api-app-chart-lint', 240000);
    },
  },
});
