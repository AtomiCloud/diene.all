import { expectGreen, expectRedWithDiagnostic } from './lib/helpers.ts';

const gate = 'nix develop .#ci -c ./scripts/validate/go-workflows.sh';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-go-workflow-wiring-green',
      description: 'Every Go reusable workflow job resolves to a cached, self-contained CI script.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'go-workflow-wiring');
      },
    },
    {
      name: 'mutation-go-workflow-wiring-caught',
      description: 'A Go reusable workflow the gate cannot parse must turn it red instead of passing unread.',
      kind: 'mutation',
      async run(repo: any) {
        const paths = (await repo.glob('.github/workflows/⚡reusable-go-*.yaml')).sort();
        if (paths.length === 0) {
          throw new Error('no Go reusable workflow target found');
        }
        const original = await repo.read(paths[0]);
        try {
          // An indentation tab is invalid YAML yet leaves the CI script reference greppable.
          await repo.write(paths[0], `${original}\n\t- [unterminated\n`);
          await expectRedWithDiagnostic(repo, gate, 'go-workflow-wiring', /could not parse Go reusable workflow/);
        } finally {
          await repo.write(paths[0], original);
        }
      },
    },
  ],
};
