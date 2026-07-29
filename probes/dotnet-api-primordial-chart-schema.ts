import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRedBecause } from './lib/helpers.ts';

// goals/dotnet-api.md L48: primordial-chart schema [gate] — EVERY primordial-chart values file
// validates against its schema; sabotage: supply one schema-invalid value -> red.
const CHART = 'infra/primordial_chart';

// Its own invocation path, distinct from the bare metadata lint row (S26): every values file is
// linted EXPLICITLY with -f, so a landscape overlay that violates the schema is caught rather
// than only the default layer.
const GATE =
  `nix develop .#ci -c bash -c 'set -e; n=0; for v in ${CHART}/values*.yaml; do ` +
  `helm lint ${CHART} -f "$v"; n=$((n+1)); done; test "$n" -gt 0; echo "schema-validated $n values file(s)"'`;

// Asserted by the mutation arm so `caught` cannot be satisfied by an unrelated failure. This
// names the SCHEMA-PATTERN mechanism rather than merely "a values file was rejected". Verified
// directly that a violating run prints it and a healthy run does NOT, so it discriminates.
const REASON = 'does not match pattern';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-api-primordial-chart-schema-green',
    description: 'Every primordial-chart values file validates against values.schema.json.',
    async run(repo: any) {
      // `test "$n" -gt 0` inside the gate is load-bearing: a glob matching nothing would
      // otherwise loop zero times and exit 0, reporting a pass having validated nothing.
      await expectGreen(repo, GATE, 'dotnet-api-primordial-chart-schema', 300000);
    },
  },
  mutation: {
    name: 'mutation-dotnet-api-primordial-chart-schema-caught',
    description: 'A values entry violating its declared schema pattern turns the gate red.',
    async run(repo: any) {
      // Structural target: read a REQUIRED patterned string key OUT OF THE SCHEMA rather than
      // hardcoding one. A hardcoded key that later stops existing would plant nothing, and the
      // arm would then prove nothing while still looking fine.
      const schema = JSON.parse(await repo.read(`${CHART}/values.schema.json`));
      const target = (schema.required ?? []).find(
        (key: string) => schema.properties?.[key]?.type === 'string' && schema.properties?.[key]?.pattern,
      );
      if (!target) throw new Error(`${CHART}/values.schema.json declares no required patterned string key`);

      const values = await repo.read(`${CHART}/values.yaml`);
      const line = new RegExp(`^${target}:.*$`, 'm');
      if (!line.test(values)) throw new Error(`${CHART}/values.yaml does not set '${target}'`);

      // Stays valid YAML — an ordinary scalar — so the red is the schema rejecting the value,
      // not a parser choking on an unreadable file.
      await repo.write(`${CHART}/values.yaml`, values.replace(line, `${target}: NOT_A_VALID_VALUE!`));
      await expectRedBecause(repo, GATE, 'dotnet-api-primordial-chart-schema', REASON, 300000);
    },
  },
});
