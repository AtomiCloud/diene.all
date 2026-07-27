// Gate: diene_config ships a TestHelper, so its meta tier is MANDATORY.
//
// This replaces the inherited `conditional-meta-activation` probe, which
// certified the opposite behavior: that a missing TestHelper turns the meta
// runner into a successful no-op and lets CI skip its meta jobs. For a
// YES-TestHelper library that guarantee is a hole — deleting the meta suite
// would produce a green CI run that uploads no TestHelper coverage and no job
// ever turns red.
//
// Baseline proves the tier really runs and really emits coverage. The mutations
// prove the tier fails CLOSED when either half is removed, and that the CI job
// carries no skip condition that could resurrect the no-op.
const REUSABLE_TEST = '.github/workflows/⚡reusable-test.yaml';
const SKIP_GUARD = "hashFiles('packages/diene_config/lib/test_helper.dart') != ''";
const META_RUN =
  "nix develop .#ci --no-write-lock-file -c bash -lc 'rm -rf packages/diene_config/coverage/meta && ./scripts/ci/test.sh meta coverage'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-mandatory-meta-tier-green',
      description:
        'the meta tier runs, passes, and emits a TestHelper-only coverage ledger; CI carries no meta skip guard',
      kind: 'baseline',
      async run(repo: any) {
        const result = await repo.exec(META_RUN, { timeoutMs: 240000 });
        if (result.exitCode !== 0) {
          throw new Error(`mandatory-meta-tier: the meta tier did not pass: ${result.stderr || result.stdout}`);
        }
        const ledger = await repo.glob('packages/diene_config/coverage/meta/lcov.info');
        if (ledger.length !== 1) {
          throw new Error('mandatory-meta-tier: the meta run produced no coverage ledger');
        }
        const workflow = await repo.read(REUSABLE_TEST);
        if (workflow.includes(SKIP_GUARD)) {
          throw new Error('mandatory-meta-tier: the CI meta job still carries a TestHelper skip guard');
        }
      },
    },
    {
      name: 'mutation-absent-testhelper-fails-closed',
      description: 'a missing TestHelper makes the meta tier FAIL rather than no-op green',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const result = await repo.exec(
          "nix develop .#ci --no-write-lock-file -c bash -lc 'TEST_HELPER_PATH=lib/__probe_absent_helper__.dart ./scripts/ci/test.sh meta coverage'",
          { timeoutMs: 240000 },
        );
        if (result.exitCode === 0) {
          throw new Error('mandatory-meta-tier: an absent TestHelper still exited 0; the tier is not mandatory');
        }
      },
    },
    {
      name: 'mutation-absent-meta-suite-fails-closed',
      description: 'a missing meta test directory makes the meta tier FAIL rather than no-op green',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const result = await repo.exec(
          "nix develop .#ci --no-write-lock-file -c bash -lc 'META_TEST_PATH=test/__probe_absent_meta__ ./scripts/ci/test.sh meta coverage'",
          { timeoutMs: 240000 },
        );
        if (result.exitCode === 0) {
          throw new Error(
            'mandatory-meta-tier: an absent meta suite still exited 0; the TestHelper proof can be deleted silently',
          );
        }
      },
    },
    {
      name: 'mutation-reintroduced-skip-guard-caught',
      description: 'reintroducing a CI meta skip condition is detected',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const workflow = await repo.read(REUSABLE_TEST);
        if (workflow.includes(SKIP_GUARD)) {
          throw new Error('mandatory-meta-tier: the skip guard was already present before sabotage');
        }
        const sabotaged = workflow.replace(
          '      - name: Run ${{ inputs.mode }} tests\n',
          `      - name: Run \${{ inputs.mode }} tests\n        if: inputs.mode != 'meta' || ${SKIP_GUARD}\n`,
        );
        await repo.write(REUSABLE_TEST, sabotaged);
        if (!(await repo.read(REUSABLE_TEST)).includes(SKIP_GUARD)) {
          throw new Error('mandatory-meta-tier: sabotage did not reintroduce the skip guard');
        }
      },
    },
  ],
};
