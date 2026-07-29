import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

const CHART = 'infra/root_chart';

// Its own invocation path, distinct from the bare `helm lint` metadata row (S26): every
// values file is linted EXPLICITLY with -f, so a landscape overlay that violates the schema
// is caught rather than only the default layer.
const GATE =
  `nix develop .#ci -c bash -c 'set -e; n=0; for v in ${CHART}/values*.yaml; do ` +
  `helm lint ${CHART} -f "$v"; n=$((n+1)); done; test "$n" -gt 0; echo "schema-validated $n values file(s)"'`;

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-api-app-chart-schema-green',
    description: 'Every app-chart values file validates against values.schema.json.',
    async run(repo: any) {
      // `test "$n" -gt 0` inside the gate is load-bearing: a glob that matched nothing would
      // otherwise loop zero times and exit 0, reporting a pass having validated nothing.
      await expectGreen(repo, GATE, 'dotnet-api-app-chart-schema', 300000);
    },
  },
  mutation: {
    name: 'mutation-dotnet-api-app-chart-schema-caught',
    description: 'A values entry violating its declared schema constraint turns the gate red.',
    async run(repo: any) {
      // Structural target: pick a REQUIRED string key that the schema constrains with a
      // pattern, read its name from the schema rather than hardcoding it, and violate the
      // pattern. Naming a key that does not exist would plant nothing and prove nothing.
      const schema = JSON.parse(await repo.read(`${CHART}/values.schema.json`));
      const target = (schema.required ?? []).find(
        (key: string) => schema.properties?.[key]?.type === 'string' && schema.properties?.[key]?.pattern,
      );
      if (!target) throw new Error(`${CHART}/values.schema.json declares no required patterned string key`);

      const values = await repo.read(`${CHART}/values.yaml`);
      const line = new RegExp(`^${target}:.*$`, 'm');
      if (!line.test(values)) throw new Error(`${CHART}/values.yaml does not set '${target}'`);

      await repo.write(`${CHART}/values.yaml`, values.replace(line, `${target}: NOT_A_VALID_VALUE!`));
      await expectRed(repo, GATE, 'dotnet-api-app-chart-schema', 300000);
    },
  },
});
