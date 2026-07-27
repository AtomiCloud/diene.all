// COST CLASS: light (<30s) — `helm lint` on one chart, no cluster, no build.
//
// This is an INDEPENDENTLY INVOKED mechanism (S26): `helm lint infra/root_chart`
// is called by its own CI job and its own pre-commit hook, separately from the
// primordial chart's lint. It therefore gets its own row and its own fault; the
// two chart-lint rows never share a sabotage.
import { expectRed } from './lib/helpers.ts';

const LINT = 'nix develop .#ci -c helm lint infra/root_chart --values infra/root_chart/values.lapras.yaml';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-app-chart-lint-green',
      description: 'Helm lint accepts the go-consumer app chart through its own direct invocation.',
      kind: 'baseline',
      async run(repo: any) {
        // Assert on printed VALUES, not a bare exit 0: `helm lint` on a path that
        // is not a chart at all also has a failure mode where nothing meaningful
        // was inspected, so the healthy run must say it linted one chart and
        // failed none.
        const result = await repo.exec(LINT, { timeoutMs: 240000 });
        const transcript = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;
        if (result.exitCode !== 0) {
          throw new Error(`app-chart-lint failed on the healthy repo:\n${transcript}`);
        }
        if (!transcript.includes('1 chart(s) linted, 0 chart(s) failed')) {
          throw new Error(
            `app-chart-lint exited 0 without reporting one linted chart — refusing a vacuous pass:\n${transcript}`,
          );
        }
      },
    },
    {
      name: 'mutation-app-chart-lint-caught',
      description: 'Invalid app chart METADATA turns its own lint red.',
      kind: 'mutation',
      expectedImpact: ['app-chart-template', 'app-chart-install', 'helm-lint', 'hook-helm-lint'],
      async run(repo: any) {
        // ONE fault, in chart METADATA, distinct from the primordial row's fault:
        // `type` must be `application` or `library`. Helm's own loader rejects it,
        // so this is a real validated rule and not a deleted subject.
        await repo.patch('infra/root_chart/Chart.yaml', {
          find: 'type: application',
          replace: 'type: not-a-chart-type',
        });
        await expectRed(repo, LINT, 'app-chart-lint');
      },
    },
  ],
};
