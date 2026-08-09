import { expectGreen, expectRedBecause } from './lib/helpers.ts';

const releaseWorkflow = '.github/workflows/release.yaml';

async function assertTrackedReleaseWorkflow(repo: any): Promise<void> {
  const subject = await repo.exec(`test -f ${releaseWorkflow} && git ls-files --error-unmatch -- ${releaseWorkflow}`);
  if (subject.exitCode !== 0) {
    throw new Error(`release-workflow-concurrency: required tracked subject '${releaseWorkflow}' is missing`);
  }
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-release-workflow-concurrency-green',
      description: 'Release uses the single release concurrency group.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c dlint workflow-policy', 'release-workflow-concurrency');
      },
    },
    {
      name: 'mutation-release-workflow-concurrency-caught',
      description: 'A focused sabotage must turn the release-workflow-concurrency mechanism red.',
      kind: 'mutation',
      expectedImpact: ['release-workflow-trigger'],
      async run(repo: any) {
        await assertTrackedReleaseWorkflow(repo);
        await repo.patch(releaseWorkflow, { find: '  group: release', replace: '  group: broken' });
        await expectRedBecause(
          repo,
          'nix develop .#ci -c dlint workflow-policy',
          'release-workflow-concurrency',
          ['release concurrency group must be release'],
          { forbidden: ['does not exist', 'Release trigger conforms', 'Release concurrency conforms', 'DISAGREEMENT'] },
        );
      },
    },
  ],
};
