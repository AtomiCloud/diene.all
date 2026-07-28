import { expectGreen, expectRed } from './lib/helpers.ts';
import { breakGoWorkflow } from './lib/go.ts';

const gate = 'nix develop .#ci -c ./scripts/validate/workflows.sh wiring';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-go-workflow-wiring-green',
      description: 'Every Go CI job resolves to an existing self-contained script.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'go-workflow-wiring');
      },
    },
    {
      name: 'mutation-go-workflow-wiring-caught',
      description: 'Pointing one Go reusable at a missing script must turn wiring red.',
      kind: 'mutation',
      expectedImpact: ['workflow-wiring'],
      async run(repo: any) {
        await breakGoWorkflow(repo);
        await expectRed(repo, gate, 'go-workflow-wiring');
      },
    },
  ],
};
