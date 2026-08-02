import { expectGreen, expectRedWithDiagnostic } from './lib/helpers.ts';
import { breakGoWorkflow } from './lib/go.ts';

const gate = 'nix develop .#ci -c ./scripts/validate/workflows.sh wiring';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-go-workflow-wiring-green',
      description: 'Every Go CI job resolves to an existing self-contained script.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'go-workflow-wiring');
      },
    },
    {
      name: 'mutation-go-workflow-wiring-caught',
      description: 'Pointing one Go reusable at a missing script must turn wiring red.',
      kind: 'mutation',
      async run(repo: any) {
        await breakGoWorkflow(repo);
        await expectRedWithDiagnostic(repo, gate, 'go-workflow-wiring', /workflow references missing script/);
      },
    },
    {
      name: 'mutation-go-workflow-wiring-unparseable-caught',
      description: 'A Go reusable workflow the gate cannot parse must turn wiring red instead of passing unread.',
      kind: 'mutation',
      async run(repo: any) {
        const paths = (await repo.glob('.github/workflows/⚡reusable-go-*.yaml')).sort();
        if (paths.length === 0) {
          throw new Error('no Go reusable workflow target found');
        }
        // An indentation tab is invalid YAML yet leaves the CI script reference greppable.
        await repo.write(paths[0], `${await repo.read(paths[0])}\n\t- [unterminated\n`);
        await expectRedWithDiagnostic(repo, gate, 'go-workflow-wiring', /could not parse reusable workflow/);
      },
    },
  ],
};
