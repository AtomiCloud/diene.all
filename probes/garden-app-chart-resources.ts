// Cost: light (<5s) — a glob sweep, no shell.
//
// Two things make this row worth having on top of the Garden chart's gates: the
// per-profile values must exist for all SEVEN ratified profiles (a missing one is
// a landscape that quietly cannot be deployed, and a render loop over a glob would
// not notice), and the negative fixture must exist, because the schema gate's
// refusal half is only real while there is something to refuse.
const requiredArtifacts = [
  'infra/Dockerfile.garden',
  'infra/garden_app_chart/Chart.yaml',
  'infra/garden_app_chart/values.yaml',
  'infra/garden_app_chart/values.schema.json',
  'infra/garden_app_chart/README.md',
  'infra/garden_app_chart/templates/_helpers.tpl',
  'infra/garden_app_chart/templates/deployment.yaml',
  'infra/garden_app_chart/templates/service.yaml',
  'infra/garden_app_chart/templates/serviceaccount.yaml',
  // The negative fixture the schema gate flips.
  'infra/garden_app_chart/profiles/rejected-hosted-boron.yaml',
] as const;

const profiles = ['lapras', 'ditto', 'rotom', 'absol', 'eevee', 'plusle', 'minun'] as const;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'presence-garden-app-chart-resources',
      description:
        'The image recipe, the Garden chart root and schema, its owned workload templates, all seven profile values, and the negative fixture exist.',
      kind: 'baseline',
      async run(repo: any) {
        for (const artifact of requiredArtifacts) {
          if ((await repo.glob(artifact)).length !== 1) {
            throw new Error(`missing Garden chart artifact: ${artifact}`);
          }
        }
        for (const profile of profiles) {
          const path = `infra/garden_app_chart/profiles/${profile}.yaml`;
          if ((await repo.glob(path)).length !== 1) {
            throw new Error(`missing values for ratified Garden profile '${profile}': ${path}`);
          }
        }
      },
    },
  ],
};
