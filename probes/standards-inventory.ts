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

const contributorReferences = ['checklist.md', 'classification.md', 'frontmatter.md', 'structure.md', 'workflow.md'];

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'presence-standards-inventory',
      description: 'All twelve agnostic standards, their thin triggers, contributor references, and the C0 slot exist.',
      kind: 'baseline',
      async run(repo: any) {
        for (const topic of topics) {
          if ((await repo.glob(`docs/standards/${topic}/index.md`)).length !== 1) {
            throw new Error(`missing shared standard index: ${topic}`);
          }
          if ((await repo.glob(`.claude/skills/${topic}/SKILL.md`)).length !== 1) {
            throw new Error(`missing shared standard skill: ${topic}`);
          }
        }

        for (const reference of contributorReferences) {
          if ((await repo.glob(`docs/standards/contributor-docs/${reference}`)).length !== 1) {
            throw new Error(`missing contributor-docs reference: ${reference}`);
          }
        }

        if ((await repo.glob('docs/standards/contracts/README.md')).length !== 1) {
          throw new Error('the reserved C0 contracts slot is missing');
        }
      },
    },
  ],
};
