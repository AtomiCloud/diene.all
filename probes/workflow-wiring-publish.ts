import { expectGreen, expectRed } from './lib/helpers.ts';

const WIRING = 'nix develop .#ci -c ./scripts/validate/workflows.sh wiring';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-workflow-wiring-publish-green',
      description: 'The CD publish job resolves to its reusable workflow.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, WIRING, 'workflow-wiring-publish');
      },
    },
    {
      name: 'mutation-workflow-wiring-publish-caught',
      description: 'Pointing the publish job at a missing reusable workflow must redden wiring.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const workflow = '.github/workflows/cd.yaml';
        const source = await repo.read(workflow);
        await repo.write(workflow, source.replace('⚡reusable-publish.yaml', '⚡reusable-does-not-exist.yaml'));
        await expectRed(repo, WIRING, 'workflow-wiring-publish');
      },
    },
  ],
};
