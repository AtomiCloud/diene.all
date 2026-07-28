// COST CLASS: light (<30s) — `helm lint` on one chart, no cluster, no build.
//
// The primordial chart's lint is INDEPENDENTLY INVOKED (S26) from the app chart's:
// the `helm-primordial` CI job points `⚡reusable-helm.yaml` at
// `./infra/primordial_chart`, a separate invocation from the app chart's job. So it
// carries its own row and its own DISTINCT metadata fault.
import { expectRed } from './lib/helpers.ts';

const LINT = 'nix develop .#ci -c helm lint infra/primordial_chart --values infra/primordial_chart/values.lapras.yaml';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-primordial-chart-lint-green',
      description: 'Helm lint accepts the primordial chart independently of the app chart.',
      kind: 'baseline',
      async run(repo: any) {
        const result = await repo.exec(LINT, { timeoutMs: 240000 });
        const transcript = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;
        if (result.exitCode !== 0) {
          throw new Error(`primordial-chart-lint failed on the healthy repo:\n${transcript}`);
        }
        if (!transcript.includes('1 chart(s) linted, 0 chart(s) failed')) {
          throw new Error(
            `primordial-chart-lint exited 0 without reporting one linted chart — refusing a vacuous pass:\n${transcript}`,
          );
        }
      },
    },
    {
      name: 'mutation-primordial-chart-lint-caught',
      description: 'Invalid primordial chart METADATA turns its own lint red.',
      kind: 'mutation',
      expectedImpact: ['primordial-chart-template', 'chart-install'],
      async run(repo: any) {
        // ONE fault, in chart METADATA, DIFFERENT from the app chart row's fault:
        // `version` must be valid SemVer. Helm validates it in its own loader, and
        // it is also the field CD pins to the one shared semver, so a chart that
        // cannot carry a valid version could never be promoted.
        await repo.patch('infra/primordial_chart/Chart.yaml', {
          find: 'version: 0.1.0',
          replace: 'version: not-a-semver',
        });
        await expectRed(repo, LINT, 'primordial-chart-lint');
      },
    },
  ],
};
