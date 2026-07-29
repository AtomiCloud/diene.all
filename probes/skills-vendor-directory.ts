// The previous version globbed `.claude/skills/vendor/**` and failed only on length 0. But
// `scripts/local/skills-sync.sh` TOUCHES A `.gitkeep`, so an EMPTY vendor tree still returns one
// path and the row passed. It detected the directory being ABSENT but not being EMPTY — the
// exact case removed from `skills-sync.ts`, surviving one row over in the presence row about the
// SAME artefact. Measured, not inferred: gutting the tree to just `.gitkeep` passed, while
// removing the directory outright failed, so the two conditions were genuinely distinguishable.
//
// The floors below are LITERALS. An expectation computed from the thing it validates cannot
// detect that thing being gutted, which is precisely how the previous version failed: the only
// entry it counted was one the synchroniser creates unconditionally.
//
// Presence rows have no sabotage arm by design, so nothing here ever poses the question on its
// own — which is why the floor has to be stated rather than derived.
const MIN_PACKAGES = 1;
const MIN_SKILLS = 1;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'presence-skills-vendor-directory',
      description: 'The resolver-owned vendored skills directory exists and is POPULATED.',
      kind: 'baseline',
      async run(repo: any) {
        const paths = await repo.glob('.claude/skills/vendor/**');
        if (paths.length === 0) {
          throw new Error('.claude/skills/vendor is missing');
        }

        // `.gitkeep` is created unconditionally by the synchroniser, so it is evidence that the
        // script RAN, never that it vendored anything. Excluded deliberately.
        const entries = paths.filter((p: string) => !p.endsWith('.gitkeep'));
        const skills = entries.filter((p: string) => p.endsWith('SKILL.md'));
        const packages = new Set(
          entries
            .map((p: string) => p.replace(/^\.claude\/skills\/vendor\//, '').split('/')[0])
            .filter((segment: string) => segment.length > 0),
        );

        if (packages.size < MIN_PACKAGES || skills.length < MIN_SKILLS) {
          throw new Error(
            `.claude/skills/vendor is EMPTY: ${packages.size} package(s) and ${skills.length} SKILL.md ` +
              `(floors ${MIN_PACKAGES}/${MIN_SKILLS}); a tree containing only .gitkeep means the ` +
              `synchroniser ran and vendored nothing`,
          );
        }

        // Report WHAT was verified, so the row cannot read as a pass that checked nothing.
        console.log(`vendored ${packages.size} package(s), ${skills.length} SKILL.md file(s)`);
      },
    },
  ],
};
