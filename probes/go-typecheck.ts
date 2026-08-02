import { expectGreen, expectRedWithDiagnostic, restoreProbeState } from './lib/helpers.ts';
import { plantGoFile } from './lib/go.ts';

const gate = 'nix develop .#ci -c pls typecheck';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-go-typecheck-green',
      description: 'Go source packages compile through the dedicated typecheck entrypoint.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'go-typecheck');
      },
    },
    {
      name: 'mutation-go-typecheck-caught',
      description: 'A native Go type error must turn the typecheck gate red.',
      kind: 'mutation',
      expectedImpact: [
        'unit-tests',
        'hook-golangci-lint',
        'govulncheck',
        'unit-coverage-scope',
        'deadcode-whole-repo',
        'deadcode-production',
        'build-artifact',
        'sample-domain-journey',
      ],
      async run(repo: any) {
        const planted = await plantGoFile(
          repo,
          'lib/**/*.go',
          'probe_type_error.go',
          'var ProbeTypeError int = "wrong"',
        );
        try {
          await expectRedWithDiagnostic(repo, gate, 'go-typecheck', /cannot use "wrong" .* as int value/);
        } finally {
          await restoreProbeState(repo, [planted]);
        }
      },
    },
  ],
};
