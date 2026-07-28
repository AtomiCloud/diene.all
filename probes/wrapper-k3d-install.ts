export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-wrapper-k3d-install-green',
      description:
        'The lapras stack installs on sandbox-unique ephemeral k3d, reaches healthy pods, and round-trips through local OCI.',
      kind: 'baseline',
      async run(repo: any) {
        const result = await repo.exec(
          'K3D_ISOLATE_BY_PATH=true nix develop .#default -c ./scripts/validate/helm-wrapper-k3d.sh',
          {
            timeoutMs: 600000,
          },
        );
        if (result.exitCode !== 0) {
          throw new Error(`wrapper-k3d-install failed: ${result.stderr || result.stdout}`);
        }
      },
    },
  ],
};
