// Gate (static wiring): the CI package-validate job must reference the reusable
// package-validate workflow, which in turn must invoke a script that exists on
// disk. Sabotage points the reusable workflow at a missing script and proves the
// wiring check no longer resolves end to end.
const CI = '.github/workflows/ci.yaml';
const REUSABLE = '.github/workflows/⚡reusable-package-validate.yaml';
const USES = 'uses: ./.github/workflows/⚡reusable-package-validate.yaml';

async function wiringResolves(repo: any): Promise<boolean> {
  const ci = await repo.read(CI);
  if (!ci.includes(USES)) {
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
      name: 'baseline-package-validate-workflow-wiring-green',
      description: 'ci.yaml → reusable-package-validate.yaml → package-validate.sh resolves end to end',
      kind: 'baseline',
      async run(repo: any) {
        if (!(await wiringResolves(repo))) {
          throw new Error('package-validate-workflow-wiring: the package-validate wiring does not resolve');
        }
      },
    },
    {
      name: 'mutation-package-validate-workflow-wiring-caught',
      description: 'the wiring check detects the reusable workflow pointing at a missing script',
      kind: 'mutation',
      expectedImpact: ['workflow-wiring'],
      async run(repo: any) {
        if (!(await wiringResolves(repo))) {
          throw new Error('package-validate-workflow-wiring: wiring already broken before sabotage');
        }
        const reusable = await repo.read(REUSABLE);
        try {
          await repo.write(REUSABLE, reusable.replace('package-validate.sh', 'package-validate-missing.sh'));
          if (await wiringResolves(repo)) {
            throw new Error('package-validate-workflow-wiring: wiring survived sabotage');
          }
        } finally {
          await repo.write(REUSABLE, reusable);
        }
      },
    },
  ],
};
