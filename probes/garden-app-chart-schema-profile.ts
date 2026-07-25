import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: medium (<2min) — the full helm rail: vendor, lint both, render the
// primordial chart, render all seven profiles, assert the negative fixture is
// refused, and check ownership. No cluster (the install smoke inside the rail is
// its own row and self-skips where no daemon is reachable).
//
// The schema is what makes a hosted-Boron or public-callback exposure
// UNREPRESENTABLE rather than merely discouraged, so the baseline has two halves:
// all seven ratified profiles render, and the negative fixture is REFUSED. A gate
// that only proved the seven would stay green after the refusal stopped working,
// which is the entire reason the fixture exists.
const command = "nix develop .#ci -c bash -lc 'HELM_SMOKE=0 ./scripts/ci/helm.sh'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-garden-app-chart-schema-profile-green',
      description:
        'All seven ratified Garden profiles render, and the hosted-Boron negative fixture is refused by the values schema.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'garden-app-chart-schema-profile');
      },
    },
    {
      name: 'mutation-garden-app-chart-schema-profile-caught',
      description:
        'Removing the constraints that make a hosted-Boron exposure unrepresentable lets the negative fixture render, turning the refusal half of the rail red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // A hosted vcluster claiming boron-direct is asking for an edge stack this
        // chart never installs: the surface simply never comes up and nothing says
        // why. The schema is the only place that can refuse it in advance.
        //
        // The fixture is deliberately over-determined — it violates the class
        // enum, the callbackMode const, AND the hosted-rail rules at once — so
        // loosening any single one leaves it correctly refused. This mutation is
        // therefore ONE act with four parts: drop every guard that stands between
        // that declaration and a render.
        const path = 'infra/garden_app_chart/values.schema.json';
        const schema = JSON.parse(await repo.read(path));
        const exposure = schema.properties.exposure.properties;
        exposure.class.enum = [...exposure.class.enum, 'public-callback'];
        delete exposure.callbackMode.const;
        schema.allOf = schema.allOf.filter(
          (rule: any) =>
            rule.then?.properties?.exposure?.properties?.mode?.const !== 'entei-service-sync' &&
            rule.then?.properties?.profile?.const !== 'lapras',
        );
        await repo.write(path, `${JSON.stringify(schema, null, 2)}\n`);
        await expectBunRed(repo, command, 'garden-app-chart-schema-profile');
      },
    },
  ],
};
