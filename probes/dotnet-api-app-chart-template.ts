import { defineSmoke } from './lib/definition.ts';

const CHART = 'infra/root_chart';

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-api-app-chart-template-green',
    description: 'The app chart renders runtime resources for every values file.',
    async run(repo: any) {
      const files = await repo.glob(`${CHART}/values*.yaml`);
      if (files.length === 0) throw new Error(`${CHART} declares no values files to render`);

      for (const file of files) {
        const result = await repo.exec(`nix develop .#ci -c helm template dotnet-api ${CHART} -f ${file}`, {
          timeoutMs: 240000,
        });
        if (result.exitCode !== 0) {
          throw new Error(`app-chart template failed for ${file}: ${result.stderr || result.stdout}`);
        }
        // Assert the ARTIFACT, not the exit code: a template that renders nothing exits 0.
        const kinds = (result.stdout.match(/^kind:/gm) ?? []).length;
        if (kinds === 0) throw new Error(`app-chart template rendered zero resources for ${file}`);
      }
    },
  },
});
