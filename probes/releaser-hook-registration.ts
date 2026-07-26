export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'presence-releaser-hook-registration',
      description: 'The published releaser commit hook is registered against the unified config.',
      kind: 'baseline',
      async run(repo: any) {
        const source = await repo.read('nix/pre-commit.nix');
        if (!source.includes('a-releaser-commit') || !source.includes('releaser lint-commit -c atomi_release.yaml')) {
          throw new Error('the releaser commit hook registration is missing');
        }
      },
    },
  ],
};
