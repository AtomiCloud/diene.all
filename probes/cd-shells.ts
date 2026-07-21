export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'presence-cd-shells',
      description: 'The platform-specific iOS and Android CD shells are declared.',
      kind: 'baseline',
      async run(repo: any) {
        const source = await repo.read('nix/shells.nix');
        for (const shell of ['cd-ios', 'cd-android']) {
          if (!source.includes(`${shell} = pkgs.mkShell`)) {
            throw new Error(`missing Nix shell: ${shell}`);
          }
        }
      },
    },
  ],
};
