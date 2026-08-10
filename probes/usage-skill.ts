// Presence: the consumer usage skill ships with the package — its SKILL.md
// declares the expected skill name in frontmatter and its patterns companion
// exists.
const SKILL_DIR = 'packages/diene_api_engine/skills/diene-api-engine-usage';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'baseline-usage-skill-present',
      description: 'the usage skill exists with the expected frontmatter name and patterns companion',
      kind: 'baseline',
      async run(repo: any) {
        const skill = await repo.read(`${SKILL_DIR}/SKILL.md`);
        const frontmatter = skill.match(/^---\n([\s\S]*?)\n---/);
        if (!frontmatter) {
          throw new Error('usage-skill: SKILL.md has no frontmatter block');
        }
        const name = frontmatter[1].match(/^name:\s*(.+)$/m)?.[1]?.trim();
        if (name !== 'diene-api-engine-usage') {
          throw new Error(`usage-skill: unexpected skill name ${name ?? '(none)'}`);
        }
        if ((await repo.glob(`${SKILL_DIR}/patterns.md`)).length !== 1) {
          throw new Error('usage-skill: patterns.md companion is missing');
        }
      },
    },
  ],
};
