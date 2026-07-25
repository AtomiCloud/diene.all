export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-service-tree-app-block-present',
      description: 'The base configuration carries the full service-tree app block.',
      kind: 'baseline',
      async run(repo: any) {
        const result = await repo.exec(
          "nix develop .#ci -c bash -lc 'yq -e '\\''.app.landscape and .app.platform and .app.service and .app.module and .app.version'\\'' config/settings.yaml'",
          { timeoutMs: 120000 },
        );
        if (result.exitCode !== 0) {
          throw new Error(
            `service-tree app block incomplete in config/settings.yaml: ${result.stderr || result.stdout}`,
          );
        }
      },
    },
  ],
};
