import { expectGreen, expectRedWithDiagnostic, restoreProbeState } from './lib/helpers.ts';

// The whole-repository staticcheck component, invoked directly rather than through the composite dispatcher.
const gate = 'nix develop .#ci -c ./scripts/local/staticcheck-whole.sh';

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
      name: 'baseline-staticcheck-whole-green',
      description: 'Staticcheck finds no violation in the healthy repository with test analysis enabled.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'staticcheck-whole-repo');
      },
    },
    {
      name: 'mutation-staticcheck-whole-caught',
      description: 'A test-tier staticcheck violation must turn the whole-repository staticcheck component red.',
      kind: 'mutation',
      async run(repo: any) {
        const planted = await plantUnitTestFile(repo, 'probe_staticcheck_whole_test.go', discardedPureResult);
        try {
          await expectRedWithDiagnostic(
            repo,
            gate,
            'staticcheck-whole-repo',
            /probe_staticcheck_whole_test\.go:\d+:\d+: ToUpper doesn't have side effects and its return value is ignored \(SA4017\)/,
          );
        } finally {
          await restoreProbeState(repo, [planted]);
        }
      },
    },
  ],
};
