import { expectGreen, expectRedWithDiagnostic, restoreProbeState } from './lib/helpers.ts';
import { plantGoFile } from './lib/go.ts';

// Per-process golangci cache. This node's baseline and mutation arms run concurrently
// over one sandbox, and a shared cache lets one arm answer with the other arm's result.
// It lives on the gate rather than inside expectGreen because the helpers are required
// to hand repo.exec the caller's bytes unchanged (probes/lib/helpers.test.ts asserts it).
const gate =
  'GOLANGCI_LINT_CACHE="$PWD/.git/cyanprint-golangci-cache-$$" nix develop .#ci -c pre-commit run a-golangci-lint --all-files';

// Plant beside a structural Go target so sample renames cannot defuse the probe.
const goSources = 'lib/**/*.go';
const fixture = 'probe_ineffectual_assignment.go';

// Export the fixture so ineffassign, not unused, owns the red diagnostic.
const ineffectualAssignment = [
  'func ProbeIneffectualAssignment() string {',
  '\tvalue := "probe"',
  '\tvalue = "probe-sabotage"',
  '\treturn value',
  '}',
].join('\n');

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-golangci-hook-green',
      description: 'The generated golangci-lint hook passes the healthy Go source.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'hook-golangci-lint');
      },
    },
    {
      name: 'mutation-golangci-hook-caught',
      description: 'A native ineffassign violation must turn the owning hook red.',
      kind: 'mutation',
      async run(repo: any) {
        const planted = await plantGoFile(repo, goSources, fixture, ineffectualAssignment);
        try {
          await expectRedWithDiagnostic(
            repo,
            gate,
            'hook-golangci-lint',
            /probe_ineffectual_assignment\.go:\d+:\d+: ineffectual assignment to \w+ \(ineffassign\)/,
          );
        } finally {
          await restoreProbeState(repo, [planted]);
        }
      },
    },
  ],
};
