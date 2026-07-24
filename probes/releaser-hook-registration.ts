export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'presence-releaser-hook-registration',
      description:
        'The conventional-commit hook is registered against the unified config. dart-lib uses the published gitlint tool (the tools/releaser stand-in) instead of the not-yet-published `releaser lint-commit`.',
      kind: 'baseline',
      async run(repo: any) {
        const source = await repo.read('nix/pre-commit.nix');
        if (!source.includes('a-releaser-commit') || !source.includes('gitlint --staged --msg-filename')) {
          throw new Error('the conventional-commit (gitlint) hook registration is missing');
        }
      },
    },
  ],
};
