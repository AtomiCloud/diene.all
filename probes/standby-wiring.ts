// Cost: light (<5s) — a workflow read, no shell.
//
// The standby rail's VALUE is that it exists on every release path: the CF-outage
// posture is only real if the standby artifact is built by the same run that
// uploads the Worker. That is a wiring property of the workflows, so it is checked
// structurally here (the standby BUILD itself is proven by the standby smoke).
const CD = '.github/workflows/cd.yaml';
const CI = '.github/workflows/ci.yaml';

const wired = async (repo: any): Promise<boolean> => {
  const cd = await repo.read(CD);
  const ci = await repo.read(CI);
  const cdHasUpload = /^  upload:$/m.test(cd) && cd.includes('⚡reusable-upload.yaml');
  const cdHasStandby = /^  standby:$/m.test(cd) && cd.includes('⚡reusable-standby.yaml');
  const ciReachesStandby = /^  standby:$/m.test(ci) && ci.includes('⚡reusable-standby.yaml');
  return cdHasUpload && cdHasStandby && ciReachesStandby;
};

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-standby-wiring-green',
      description:
        'Both delivery orchestrators reach the standby rail: the release path builds the standby artifact alongside the Worker upload.',
      kind: 'baseline',
      async run(repo: any) {
        if (!(await wired(repo))) {
          throw new Error('the standby rail is not wired into both the CI and CD orchestrators');
        }
      },
    },
    {
      name: 'mutation-standby-wiring-caught',
      description: 'Removing the standby job from the release orchestrator turns the wiring check red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // Releases keep passing and the standby host keeps serving whatever it last
        // received — the rail silently ages out, and that is discovered during the
        // outage it exists for.
        const source = await repo.read(CD);
        await repo.write(
          CD,
          source.replace(/\n  standby:\n(?:.*\n)*?    uses: \.\/\.github\/workflows\/⚡reusable-standby\.yaml\n/, '\n'),
        );
        if (await wired(repo)) {
          throw new Error('standby-wiring stayed green after the standby job was removed from cd.yaml');
        }
      },
    },
  ],
};
