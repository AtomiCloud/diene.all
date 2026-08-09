export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-config-dev-yaml-present',
      description: 'The single local-dev control file exists and parses as YAML.',
      kind: 'baseline',
      async run(repo: any) {
        const result = await repo.exec("nix develop .#ci -c bash -lc 'yq -e . config/dev.yaml >/dev/null'", {
          timeoutMs: 120000,
        });
        if (result.exitCode !== 0) {
          throw new Error(`config/dev.yaml missing or unparseable: ${result.stderr || result.stdout}`);
        }
      },
    },
  ],
};
