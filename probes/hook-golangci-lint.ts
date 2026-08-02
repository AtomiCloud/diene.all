import { expectGreen, expectRedWithDiagnostic, restoreProbeState } from './lib/helpers.ts';
import { plantGoFile } from './lib/go.ts';

const gate = 'nix develop .#ci -c pre-commit run a-golangci-lint --all-files';

// The violation is planted beside whichever Go source the glob selects instead of
// rewriting a named seed function: a probe keyed on one file and on the body of
// one seed implementation stops proving the hook the moment that seed is renamed,
// rewritten, or replaced by the template consumer.
const goSources = 'lib/**/*.go';
const fixture = 'probe_ineffectual_assignment.go';

// Exported on purpose. An unexported probe symbol is dead code, so `unused` would
// turn the hook red by itself and the ineffassign finding under test would never
// have to fire.
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
          // The fixture is untracked, so restoring the git snapshot alone would hand
          // the next probe a repository that is still lint-red.
          await restoreProbeState(repo, [planted]);
        }
      },
    },
  ],
};
