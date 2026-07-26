export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'presence-usage-skill',
      description: 'The shipped usage skill and its assets exist and the SKILL.md frontmatter parses.',
      kind: 'baseline',
      async run(repo: any) {
        const source = await repo.read('skills/diene-auth-engine-usage/SKILL.md');
        const frontmatter = source.match(/^---\n([\s\S]*?)\n---/);
        if (!frontmatter) {
          throw new Error('usage skill frontmatter is missing');
        }
        const name = frontmatter[1].match(/^name:\s*(.+)$/m)?.[1]?.trim();
        if (name !== 'diene-auth-engine-usage') {
          throw new Error(`usage skill name mismatch: ${name ?? 'missing'}`);
        }
        if ((await repo.glob('skills/diene-auth-engine-usage/patterns.md')).length !== 1) {
          throw new Error('usage skill assets are missing');
        }
      },
    },
  ],
};
