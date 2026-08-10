import { expectGreen, expectRed } from './lib/helpers.ts';

const WIRING = 'nix develop .#ci -c ./scripts/validate/workflows.sh wiring';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-workflow-wiring-package-validate-green',
      description: 'The CI package-validate job resolves to its reusable workflow.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, WIRING, 'workflow-wiring-package-validate');
      },
    },
    {
      name: 'mutation-workflow-wiring-package-validate-caught',
      description: 'Pointing the package-validate job at a missing reusable workflow must redden wiring.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const workflow = '.github/workflows/ci.yaml';
        const source = await repo.read(workflow);
        await repo.write(
          workflow,
          source.replace('⚡reusable-package-validate.yaml', '⚡reusable-does-not-exist.yaml'),
        );
        await expectRed(repo, WIRING, 'workflow-wiring-package-validate');
      },
    },
  ],
};
