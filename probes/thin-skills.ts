const topics = [
  'authorization',
  'contributor-docs',
  'datetime',
  'domain-driven-design',
  'functional-practices',
  'software-design-philosophy',
  'solid-principles',
  'stateless-oop-di',
  'testing',
  'three-layer-architecture',
  'utilities',
  'validation',
] as const;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'presence-thin-skills',
      description: 'The curated thin-trigger files and their parseable names exist; thinness remains review-owned.',
      kind: 'baseline',
      async run(repo: any) {
        for (const topic of topics) {
          const source = await repo.read(`.claude/skills/${topic}/SKILL.md`);
          const frontmatter = source.match(/^---\n([\s\S]*?)\n---/);
          if (!frontmatter) {
            throw new Error(`skill frontmatter is missing: ${topic}`);
          }
          const name = frontmatter[1].match(/^name:\s*(.+)$/m)?.[1]?.trim();
          if (name !== topic) {
            throw new Error(`skill name mismatch for ${topic}: ${name ?? 'missing'}`);
          }
        }
      },
    },
  ],
};
