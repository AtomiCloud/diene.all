import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

// The previous version asserted self-cleaning and idempotence and NOTHING ELSE — so an EMPTY
// vendor tree passed every one of its checks: the planted stale entry is gone, the two copies
// are identical, and `diff -ru` of nothing against nothing exits 0. It ran, it exited 0, and it
// never read the artefact it is named for.
//
// This asserts the SPECIFIED contract: the resolver-owned vendor tree
// `.claude/skills/vendor/<package>/**` (goals/workspace.md, goals/shared.md). It does NOT assert
// `manifest.json` — that is an unspecified consumer-layer addition, and pinning it would assert
// something the goal never promised.
//
// Every assertion prints the VALUE it checked, and each is one an empty run would fail.
const SYNC = './scripts/local/skills-sync.sh';

const GATE =
  `nix develop .#ci -c bash -c 'set -e; ` +
  // A planted stale entry the synchroniser must remove — kept from the original.
  `mkdir -p .claude/skills/vendor/stale; echo stale > .claude/skills/vendor/stale/SKILL.md; ` +
  `first="$(mktemp -d)"; second="$(mktemp -d)"; ` +
  `trap "rm -rf \\"$first\\" \\"$second\\"" EXIT; ` +
  `${SYNC}; ` +
  `test ! -e .claude/skills/vendor/stale || { echo "self-clean FAILED: stale entry survived"; exit 1; }; ` +
  // THE ASSERTION THE STUB LACKED: the tree must actually carry vendored skills.
  `pkgs=$(find .claude/skills/vendor -mindepth 1 -maxdepth 1 -type d | wc -l); ` +
  `skills=$(find .claude/skills/vendor -name SKILL.md | wc -l); ` +
  `test "$pkgs" -gt 0 || { echo "vendor tree has NO package directories"; exit 1; }; ` +
  `test "$skills" -gt 0 || { echo "vendor tree has NO SKILL.md files"; exit 1; }; ` +
  // Every package directory must carry a skill, so a stray empty directory cannot pass.
  `for d in .claude/skills/vendor/*/; do ` +
  `n=$(find "$d" -name SKILL.md | wc -l); ` +
  `test "$n" -gt 0 || { echo "package $d carries no SKILL.md"; exit 1; }; done; ` +
  // Idempotence, kept from the original.
  `cp -R .claude/skills/vendor/. "$first"/; ${SYNC}; cp -R .claude/skills/vendor/. "$second"/; ` +
  `diff -ru "$first" "$second"; ` +
  `echo "vendored $pkgs package(s), $skills SKILL.md file(s); self-clean ok; idempotent"'`;

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-skills-sync-green',
    description: 'The synchroniser populates the vendor tree, self-cleans, and is idempotent on a second run.',
    async run(repo: any) {
      await expectGreen(repo, GATE, 'skills-sync', 600000);
    },
  },
  mutation: {
    name: 'mutation-skills-sync-caught',
    description: 'A resolver matching no packages leaves the vendor tree EMPTY and turns the gate red.',
    async run(repo: any) {
      // Structural target: break the package-id pattern the .NET branch resolves with, so it
      // matches nothing and the tree comes back empty. That is the realistic shape of this
      // failure — a package-prefix rename — and it is EXACTLY the case the previous version
      // passed silently.
      const path = 'scripts/local/skills-sync.sh';
      const source = await repo.read(path);
      const anchor = 'PackageVersion Include="AtomiCloud\\.Diene\\.[^"]+"';
      if (!source.includes(anchor)) {
        throw new Error(`${path} no longer resolves .NET packages with the expected pattern`);
      }
      await repo.write(path, source.replace(anchor, 'PackageVersion Include="NoSuchPrefix\\.[^"]+"'));

      await expectRed(repo, GATE, 'skills-sync', 600000);
    },
  },
});
