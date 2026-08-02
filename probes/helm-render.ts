export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-helm-render-green',
      description: 'Helm accepts the deliberately empty R16 stub and renders no manifests.',
      kind: 'baseline',
      async run(repo: any) {
        const result = await repo.exec('nix develop .#ci -c helm template dotnet-base infra/root_chart');
        const output = `${result.stdout}\n${result.stderr}`.trim();
        if (result.exitCode !== 0) {
          throw new Error(`helm-render rejected the empty R16 stub: ${output}`);
        }
        if (output.length !== 0) {
          throw new Error(`the R16 stub unexpectedly rendered manifests: ${output}`);
        }
      },
    },
  ],
};
