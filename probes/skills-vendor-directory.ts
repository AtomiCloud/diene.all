export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'presence-skills-vendor-directory',
      description: 'The resolver-owned vendored skills directory exists.',
      kind: 'baseline',
      async run(repo: any) {
        const paths = await repo.glob('.claude/skills/vendor/**');
        if (paths.length === 0) {
          throw new Error('.claude/skills/vendor is missing');
        }
      },
    },
  ],
};
