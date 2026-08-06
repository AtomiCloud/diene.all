// The ten language-agnostic topics this node owns. Parent-owned tooling
// standards are deliberately absent: their skill names do not track their
// directory names, and asserting them here would be a topology check.
// `authorization` left this node with the .NET layer that is its only user, and
// the contributor-doc segment was removed outright, so neither is asserted here
// any more — see the shared forward review.
export const topics = [
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
      name: 'presence-standards-inventory',
      description: 'All ten agnostic standards and their thin triggers exist.',
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
      },
    },
  ],
};
