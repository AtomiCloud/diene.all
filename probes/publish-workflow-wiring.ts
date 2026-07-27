// Gate (static wiring): the release pipeline (cd.yaml) must reference the
// reusable publish workflow, which in turn must invoke a publish script that
// exists on disk. Sabotage points the reusable workflow at a missing script and
// proves the wiring check no longer resolves end to end.
const CD = '.github/workflows/cd.yaml';
const REUSABLE = '.github/workflows/⚡reusable-publish.yaml';
const USES = 'uses: ./.github/workflows/⚡reusable-publish.yaml';

async function wiringResolves(repo: any): Promise<boolean> {
  const cd = await repo.read(CD);
  if (!cd.includes(USES)) {
    return false;
  }
  if ((await repo.glob(REUSABLE)).length !== 1) {
    return false;
  }
  const reusable = await repo.read(REUSABLE);
  const scriptMatch = reusable.match(/scripts\/[A-Za-z0-9_./-]+\.sh/);
  if (!scriptMatch) {
    return false;
  }
  return (await repo.glob(scriptMatch[0])).length === 1;
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'baseline-publish-workflow-wiring-green',
      description: 'cd.yaml → reusable-publish.yaml → publish.sh resolves end to end',
      kind: 'baseline',
      async run(repo: any) {
        if (!(await wiringResolves(repo))) {
          throw new Error('publish-workflow-wiring: the publish wiring does not resolve');
        }
      },
    },
    {
      name: 'mutation-publish-workflow-wiring-caught',
      description: 'the wiring check detects the reusable workflow pointing at a missing script',
      kind: 'mutation',
      expectedImpact: ['workflow-wiring'],
      async run(repo: any) {
        if (!(await wiringResolves(repo))) {
          throw new Error('publish-workflow-wiring: wiring already broken before sabotage');
        }
        const reusable = await repo.read(REUSABLE);
        await repo.write(REUSABLE, reusable.replace('publish.sh', 'publish-missing.sh'));
        if (await wiringResolves(repo)) {
          throw new Error('publish-workflow-wiring: wiring survived sabotage');
        }
      },
    },
  ],
};
