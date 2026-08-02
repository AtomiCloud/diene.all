import { expectGreen, expectRedWithDiagnostic, restoreProbeState } from './lib/helpers.ts';
import { plantGoFile } from './lib/go.ts';

// Keep the whole-repository pass independent from the composite `pls deadcode` task.
const gate = 'nix develop .#ci -c ./scripts/local/deadcode.sh whole';
// The blocking hook registration is a second enforcement mechanism for the same two invocations.
const hook = 'nix develop .#ci -c pre-commit run a-deadcode --all-files';
const hookTimeoutMs = 600000;

const deadDeclaration = 'func ProbeDead() int { return 1 }';
// The pass reports findings as deadcode's own JSON, so the fixture is proven by its entry, not by a bare name match.
const deadFinding = /"Name": "ProbeDead",[\s\S]*?"File": "[^"]*probe_dead\.go"/;

// A discarded pure result is invisible to deadcode and to a pass that skips tests, so only `staticcheck -tests=true` catches it.
const discardedPureResult = [
  'import (',
  '\t"strings"',
  '\t"testing"',
  ')',
  '',
  'func TestProbeStaticcheckWhole(t *testing.T) {',
  '\tstrings.ToUpper("probe")',
  '\tt.Log("probe")',
  '}',
].join('\n');

// plantGoFile skips `_test.go` targets, so the test-tier fixture resolves its own package.
async function plantUnitTestFile(repo: any, filename: string, declaration: string): Promise<string> {
  const paths = ((await repo.glob('tests/unit/**/*_test.go')) as string[]).sort();
  if (paths.length === 0) {
    throw new Error('no unit test package found');
  }
  const packageDeclaration = (await repo.read(paths[0])).match(/^package\s+([A-Za-z0-9_]+)/m)?.[1];
  if (!packageDeclaration) {
    throw new Error('could not infer the unit test package');
  }
  const target = `${paths[0].slice(0, paths[0].lastIndexOf('/'))}/${filename}`;
  await repo.write(target, `package ${packageDeclaration}\n\n${declaration}\n`);
  return target;
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-deadcode-whole-green',
      description: 'Deadcode and staticcheck find no unreachable code with tests included.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'deadcode-whole-repo');
      },
    },
    {
      name: 'baseline-deadcode-whole-hook-green',
      description: 'The blocking deadcode hook passes the healthy repository.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, hook, 'deadcode-whole-repo-hook', hookTimeoutMs);
      },
    },
    {
      name: 'mutation-deadcode-whole-caught',
      description: 'A dead exported function must turn the whole-repository deadcode invocation red.',
      kind: 'mutation',
      expectedImpact: ['deadcode-production', 'unit-coverage-scope'],
      async run(repo: any) {
        const planted = await plantGoFile(repo, 'lib/**/*.go', 'probe_dead.go', deadDeclaration);
        try {
          await expectRedWithDiagnostic(repo, gate, 'deadcode-whole-repo', deadFinding);
        } finally {
          await restoreProbeState(repo, [planted]);
        }
      },
    },
    {
      name: 'mutation-staticcheck-whole-caught',
      description: 'A test-tier staticcheck violation must turn the whole-repository staticcheck invocation red.',
      kind: 'mutation',
      // Deadcode and the production pass both stay green on this fixture; only linters that analyse tests see it.
      expectedImpact: ['hook-golangci-lint', 'binary-smoke'],
      async run(repo: any) {
        const planted = await plantUnitTestFile(repo, 'probe_staticcheck_whole_test.go', discardedPureResult);
        try {
          await expectRedWithDiagnostic(
            repo,
            gate,
            'deadcode-whole-repo',
            /probe_staticcheck_whole_test\.go:\d+:\d+: ToUpper doesn't have side effects and its return value is ignored \(SA4017\)/,
          );
        } finally {
          await restoreProbeState(repo, [planted]);
        }
      },
    },
    {
      name: 'mutation-deadcode-whole-hook-caught',
      description: 'A dead exported function must turn the blocking deadcode hook red.',
      kind: 'mutation',
      expectedImpact: ['deadcode-production', 'unit-coverage-scope'],
      async run(repo: any) {
        const planted = await plantGoFile(repo, 'lib/**/*.go', 'probe_dead.go', deadDeclaration);
        try {
          await expectRedWithDiagnostic(repo, hook, 'deadcode-whole-repo-hook', deadFinding, hookTimeoutMs);
        } finally {
          await restoreProbeState(repo, [planted]);
        }
      },
    },
  ],
};
