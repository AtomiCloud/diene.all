import { expectGreen, expectRed } from './lib/helpers.ts';
import { plantGoFile } from './lib/go.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-go-typecheck-green',
      description: 'Go source packages compile through the dedicated typecheck entrypoint.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c ./scripts/local/typecheck.sh', 'go-typecheck');
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
        // ### go-consumer-typecheck-impact
        // #### source: go-consumer
        // The go-base `sample-domain-journey` row was REMOVED by the sanctioned
        // fenced swap (the swap deletes its invocation path
        // `scripts/validate/sample-journey.sh` with the sample), so it is no longer
        // a co-selected control. The consumer rows a Go type error legitimately
        // reddens take its place: everything that compiles the tree.
        'cmd-entry',
        'config-layering',
        'http-auth-encryptor',
      ],
      async run(repo: any) {
        await plantGoFile(repo, 'lib/**/*.go', 'probe_type_error.go', 'var ProbeTypeError int = "wrong"');
        await expectRed(repo, 'nix develop .#ci -c ./scripts/local/typecheck.sh', 'go-typecheck');
      },
    },
  ],
};
