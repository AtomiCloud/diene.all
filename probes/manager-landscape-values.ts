import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'presence-manager-landscape-values',
      description:
        'The per-landscape values files exist and the default chart is safe (ledger-backed Note off by default; landscape overlays enable it).',
      kind: 'baseline',
      async run(repo: any) {
        for (const landscape of ['lapras', 'pichu', 'pikachu', 'raichu', 'amphoros']) {
          if ((await repo.glob(`infra/root_chart/values.${landscape}.yaml`)).length !== 1) {
            throw new Error(`missing landscape values file: values.${landscape}.yaml`);
          }
        }
        await expectGreen(
          repo,
          "nix develop .#ci -c bash -lc '" +
            'helm template t infra/root_chart | rg -q -- "--enable-note=false" && ' +
            'helm template t infra/root_chart -f infra/root_chart/values.lapras.yaml | rg -q -- "--enable-note=true"\'',
          'manager-landscape-values',
        );
      },
    },
  ],
};
