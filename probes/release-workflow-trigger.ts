import { expectGreen, expectRedBecause } from './lib/helpers.ts';

const releaseWorkflow = '.github/workflows/release.yaml';

async function assertTrackedReleaseWorkflow(repo: any): Promise<void> {
  const subject = await repo.exec(`test -f ${releaseWorkflow} && git ls-files --error-unmatch -- ${releaseWorkflow}`);
  if (subject.exitCode !== 0) {
    throw new Error(`release-workflow-trigger: required tracked subject '${releaseWorkflow}' is missing`);
  }
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-release-workflow-trigger-green',
      description: 'Release runs only after successful CI completion on main.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c dlint workflow-policy', 'release-workflow-trigger');
      },
    },
    {
      name: 'mutation-release-workflow-trigger-caught',
      description: 'A focused sabotage must turn the release-workflow-trigger mechanism red.',
      kind: 'mutation',
      expectedImpact: ['release-workflow-concurrency'],
      async run(repo: any) {
        await assertTrackedReleaseWorkflow(repo);
        await repo.patch(releaseWorkflow, {
          find: "workflows: ['CI']",
          replace: "workflows: ['Broken']",
        });
        await expectRedBecause(
          repo,
          'nix develop .#ci -c dlint workflow-policy',
          'release-workflow-trigger',
          ['release must trigger from CI'],
          { forbidden: ['does not exist', 'Release trigger conforms', 'Release concurrency conforms', 'DISAGREEMENT'] },
        );
      },
    },
  ],
};
