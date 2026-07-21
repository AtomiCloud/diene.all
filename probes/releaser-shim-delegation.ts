// Delegation guard (pure read, no execution, cannot publish). While the second
// (runtime) defect is fixed, this keeps the accepted first-defect cure intact by
// asserting the `releaser` bootstrap shim still delegates to `sg`: the package in
// nix/packages.nix must exec `${atomi.sg}/bin/sg`. If the delegation is broken the
// shim would resolve to nothing and the exit-127 boundary would return.
const SG_DELEGATION = /writeShellScriptBin "releaser"[\s\S]*?exec \$\{atomi\.sg\}\/bin\/sg "\$@"/;

async function assertShimDelegatesToSg(repo: any): Promise<void> {
  const packages = await repo.read('nix/packages.nix');
  if (!SG_DELEGATION.test(packages)) {
    throw new Error('the releaser shim no longer delegates to ${atomi.sg}/bin/sg');
  }
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git' },
  probes: [
    {
      name: 'baseline-releaser-shim-delegation-green',
      description:
        'The releaser bootstrap package in nix/packages.nix still execs ${atomi.sg}/bin/sg, preserving the accepted first-defect cure.',
      kind: 'baseline',
      async run(repo: any) {
        await assertShimDelegatesToSg(repo);
      },
    },
    {
      name: 'mutation-releaser-shim-delegation-caught',
      description:
        'Breaking the shim delegation to sg must turn the gate red, guarding against silent return to the exit-127 missing-executable defect.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch('nix/packages.nix', {
          find: 'exec ${atomi.sg}/bin/sg "$@"',
          replace: 'exec ${atomi.sg}/bin/DELETED "$@"',
        });
        let caught = false;
        try {
          await assertShimDelegatesToSg(repo);
        } catch {
          caught = true;
        }
        if (!caught) {
          throw new Error('shim-delegation gate stayed green after breaking the sg delegation');
        }
      },
    },
  ],
};
