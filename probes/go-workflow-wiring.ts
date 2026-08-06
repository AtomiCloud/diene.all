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
      description: 'A Go reusable workflow that calls a missing CI script must turn wiring red.',
      kind: 'mutation',
      async run(repo: any) {
        const paths = (await repo.glob('.github/workflows/⚡reusable-go-*.yaml')).sort();
        if (paths.length === 0) {
          throw new Error('no Go reusable workflow target found');
        }
        let target = '';
        let original = '';
        let script = '';
        for (const path of paths) {
          const source = await repo.read(path);
          const match = source.match(/\.\/scripts\/ci\/[A-Za-z0-9._/-]+[.]sh/)?.[0];
          if (match) {
            target = path;
            original = source;
            script = match;
            break;
          }
        }
        if (!target) {
          throw new Error('no Go workflow script target found');
        }
        try {
          await repo.write(target, original.replace(script, './scripts/ci/probe-missing.sh'));
          await expectRedWithDiagnostic(
            repo,
            gate,
            'go-workflow-wiring',
            /references missing script 'scripts\/ci\/probe-missing[.]sh'/,
          );
        } finally {
          await repo.write(target, original);
        }
      },
    },
  ],
};
