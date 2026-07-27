import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<25s) — vendoring plus two renders.
//
// A values schema is only a gate if something red-lights when a value leaves it,
// so the baseline proves BOTH halves: an in-enum value renders and an out-of-enum
// value is refused. The sabotage then removes the enum, which silences the second
// half while leaving the first untouched.
const command =
  'nix develop .#ci -c bash -lc \'./scripts/local/chart-vendor.sh && helm template primordial-probe infra/primordial_chart --set logtoApp.type=Traditional >/dev/null && if helm template primordial-probe infra/primordial_chart --set logtoApp.type=NotAnAppType >/dev/null 2>&1; then echo "schema accepted an out-of-enum logtoApp.type" >&2; exit 1; fi\'';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-primordial-chart-schema-green',
      description:
        'Values validate against values.schema.json: a declared application type renders and an undeclared one is refused before anything is templated.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'primordial-chart-schema');
      },
    },
    {
      name: 'mutation-primordial-chart-schema-caught',
      description:
        'Dropping the application-type enum lets an invalid value through, so the refusal half of the baseline goes red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // Without the enum, a typo'd application type reaches the operator and
        // becomes a wrong OIDC flow rather than a failed render.
        const path = 'infra/primordial_chart/values.schema.json';
        const schema = JSON.parse(await repo.read(path));
        delete schema.properties.logtoApp.properties.type.enum;
        await repo.write(path, `${JSON.stringify(schema, null, 2)}\n`);
        await expectBunRed(repo, command, 'primordial-chart-schema');
      },
    },
  ],
};
