// Gate: the meta tier is conditionally activated. When the shipped TestHelper is
// absent the local runner (`scripts/ci/test.sh meta`) is a no-op that exits 0
// without producing coverage, and the CI workflow guards its meta jobs with a
// `hashFiles(...)` conditional. Sabotage removes the workflow guard (forcing the
// meta jobs to always run) and proves the guard token is gone.
const GUARD = "hashFiles('packages/diene_problems/lib/test_helper.dart') != ''";
const REUSABLE_TEST = '.github/workflows/⚡reusable-test.yaml';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-conditional-meta-activation-green',
      description: 'the meta runner no-ops (exit 0, no coverage) when the TestHelper is absent and CI guards it',
      kind: 'baseline',
      async run(repo: any) {
        const result = await repo.exec(
          "nix develop .#ci --no-write-lock-file -c bash -lc 'rm -rf packages/diene_problems/coverage/meta && TEST_HELPER_PATH=lib/__probe_absent_helper__.dart ./scripts/ci/test.sh meta coverage'",
          { timeoutMs: 240000 },
        );
        if (result.exitCode !== 0) {
          throw new Error(
            `conditional-meta-activation: inactive meta run did not exit 0: ${result.stderr || result.stdout}`,
          );
        }
        const leftovers = await repo.glob('packages/*/coverage/meta/lcov.info');
        if (leftovers.length !== 0) {
          throw new Error('conditional-meta-activation: inactive meta run still emitted coverage');
        }
        const workflow = await repo.read(REUSABLE_TEST);
        if (!workflow.includes(GUARD)) {
          throw new Error('conditional-meta-activation: CI meta jobs are not guarded by the TestHelper conditional');
        }
      },
    },
    {
      name: 'mutation-conditional-meta-activation-caught',
      description: 'the guard check detects the CI meta conditional being forced always-on',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const workflow = await repo.read(REUSABLE_TEST);
        if (!workflow.includes(GUARD)) {
          throw new Error('conditional-meta-activation: guard token missing before sabotage');
        }
        await repo.write(REUSABLE_TEST, workflow.split(GUARD).join('true'));
        if ((await repo.read(REUSABLE_TEST)).includes(GUARD)) {
          throw new Error('conditional-meta-activation: guard survived sabotage');
        }
      },
    },
  ],
};
