import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRedBecause } from './lib/helpers.ts';

// goals/dotnet-api.md L47: primordial-chart lint [gate] — `helm lint` runs INDEPENDENTLY for the
// primordial chart; sabotage: invalidate its metadata -> red. It is a separate invocation from
// the app chart's row precisely so a lint that only ever ran against the app chart cannot pass
// for both.
const CHART = 'infra/primordial_chart';
const GATE = `nix develop .#ci -c helm lint ${CHART}`;

// The mutation arm asserts this string rather than merely asserting failure. `expectRed` alone
// would accept ANY nonzero exit — including a chart that failed to parse — and the report carries
// no stdout to tell them apart. Verified directly that helm prints this when apiVersion is
// invalid, and that a healthy lint does NOT print it, so it discriminates.
const REASON = 'is not valid. The value must be either';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-api-primordial-chart-lint-green',
    description: 'helm lint accepts the primordial chart through its own independent invocation.',
    async run(repo: any) {
      await expectGreen(repo, GATE, 'dotnet-api-primordial-chart-lint', 240000);
    },
  },
  mutation: {
    name: 'mutation-dotnet-api-primordial-chart-lint-caught',
    description: 'Invalidating the primordial chart metadata turns lint red, naming the bad apiVersion.',
    async run(repo: any) {
      // Chart.yaml stays VALID YAML under this edit — `invalid` is an ordinary scalar — so the
      // red is helm rejecting the metadata, not a parser choking on an unreadable file.
      await repo.patch(`${CHART}/Chart.yaml`, { find: 'apiVersion: v2', replace: 'apiVersion: invalid' });
      await expectRedBecause(repo, GATE, 'dotnet-api-primordial-chart-lint', [REASON], { timeoutMs: 240000 });
    },
  },
});
