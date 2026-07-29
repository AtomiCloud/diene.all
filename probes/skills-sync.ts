// DRAFT — derived bun-base probes/skills-sync.ts (NOT a port of the 315-line consumer probe).
// Kept out-of-tree until the red arm is proven + committed in one atomic step
// (shared-worktree pre-commit-stash hazard). Target: canonical bun-base branch
// worktree .worktrees/exec-bun-base-20260723T053800Z, HEAD 5e9e5c6.
//
// Derived from bun-base's ACTUAL contract:
//   - no @atomicloud/diene.* deps, no go.mod / Directory.Packages.props / .dart_tool
//   - skills-sync.sh is the OLD copy-only version: NO manifest.json, NO refusal logic
//   => assert on the VENDOR TREE (not a manifest): an empty-world sync yields a tree with
//      no diene.* package dirs ("check that there is nothing" — falsifiable), a present
//      diene skills dir DOES get vendored (so "empty" is meaningful), and a sabotage that
//      vendors spurious diene.* content is CAUGHT (the red arm).

// ─────────────────────────────────────────────────────────────────────────────
// LABEL (noel RULING A, 2026-07-29) — this asserts the SPECIFIED contract.
// This probe asserts the specified skills-sync contract: the skills vendor tree
// `.claude/skills/vendor/<package>/**` (committed, resolver-owned, self-cleaning,
// idempotent), per goals/workspace.md L179-189 and goals/shared.md L88-101. THERE IS NO
// `manifest.json` IN THE SPECIFICATION. The manifest emitted by the newer
// consumer/workspace script is an UNSPECIFIED IMPLEMENTATION ADDITION, not a requirement
// this base fails to meet — this base's copy-only synchronizer is spec-compliant, NOT
// stale. Whether the manifest SHOULD become universal is an OPEN spec-change question as
// of 2026-07-29, tracked separately (see
// exec/nodes/bun-base/evidence/skills-sync-coverage-sweep.md) — it is not a defect in
// this node.
// ─────────────────────────────────────────────────────────────────────────────

import { expectGreen, expectRed } from './lib/helpers.ts';

const vendorDir = '.claude/skills/vendor';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-skills-sync-empty-green',
      description:
        'With no diene dependencies declared, the synchronizer vendors a legitimately empty tree (no diene.* packages), removes stale vendored entries, and is idempotent on a second run.',
      kind: 'baseline',
      async run(repo: any) {
        await repo.write(`${vendorDir}/stale/SKILL.md`, 'stale\n');
        await expectGreen(
          repo,
          `nix develop .#ci -c bash -c 'set -euo pipefail; first="$(mktemp -d)"; second="$(mktemp -d)"; trap "rm -rf \\"$first\\" \\"$second\\"" EXIT; ./scripts/local/skills-sync.sh; test ! -e ${vendorDir}/stale; test -z "$(find ${vendorDir} -mindepth 1 -maxdepth 1 -name "diene.*" -print -quit)"; cp -R ${vendorDir}/. "$first"/; ./scripts/local/skills-sync.sh; cp -R ${vendorDir}/. "$second"/; diff -ru "$first" "$second"'`,
          'skills-sync',
        );
      },
    },
    {
      name: 'baseline-skills-sync-present-green',
      description:
        'When a diene package ships a skills/ directory under node_modules/@atomicloud, the synchronizer vendors it — so the empty-tree assertion is meaningful, not vacuous on a synchronizer that never copies anything.',
      kind: 'baseline',
      async run(repo: any) {
        await repo.write('node_modules/@atomicloud/diene.fixture/skills/example/SKILL.md', 'fixture skill\n');
        await expectGreen(
          repo,
          `nix develop .#ci -c bash -c 'set -euo pipefail; ./scripts/local/skills-sync.sh; test -f ${vendorDir}/diene.fixture/example/SKILL.md; test "$(cat ${vendorDir}/diene.fixture/example/SKILL.md)" = "fixture skill"'`,
          'skills-sync',
        );
      },
    },
    {
      name: 'mutation-skills-sync-spurious-vendor-caught',
      description:
        'A focused sabotage must turn the empty-tree guarantee red: if the synchronizer vendors a diene.* package that is not a declared dependency, the empty-world assertion must fail.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // Inject a spurious diene.* dir into staging just before it is moved into place.
        await repo.patch('scripts/local/skills-sync.sh', {
          find: 'rm -rf "${vendor_dir}"\n',
          replace:
            'mkdir -p "${staging}/diene.injected"; : >"${staging}/diene.injected/SKILL.md"\nrm -rf "${vendor_dir}"\n',
        });
        await expectRed(
          repo,
          `nix develop .#ci -c bash -c 'set -euo pipefail; ./scripts/local/skills-sync.sh; test -z "$(find ${vendorDir} -mindepth 1 -maxdepth 1 -name "diene.*" -print -quit)"'`,
          'skills-sync',
        );
      },
    },
  ],
};
