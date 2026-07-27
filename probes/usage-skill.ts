export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'presence-usage-skill',
      description: 'The shipped e2e usage skill and referenced e2e standard exist and its frontmatter parses.',
      kind: 'baseline',
      async run(repo: any) {
        const source = await repo.read('skills/diene-e2e-usage/SKILL.md');
        const frontmatter = source.match(/^---\n([\s\S]*?)\n---/);
        if (!frontmatter) {
          throw new Error('usage skill frontmatter is missing');
        }
        const name = frontmatter[1].match(/^name:\s*(.+)$/m)?.[1]?.trim();
        if (name !== 'diene-e2e-usage') {
          throw new Error(`usage skill name mismatch: ${name ?? 'missing'}`);
        }
        if ((await repo.glob('docs/standards/e2e/index.md')).length !== 1) {
          throw new Error('e2e usage standard is missing');
        }
      },
    },
  ],
};
