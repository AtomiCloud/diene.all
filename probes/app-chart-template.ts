// COST CLASS: light (<30s) — one `helm template`, no cluster.
//
// Proven-only smoke (no sabotage): rendering is the mechanism, and its failure
// modes are already gated by app-chart-lint. This row asserts the rendered
// ARTIFACT rather than the exit code (PROBES §2.4): the worker Deployment, the
// db-init Job carrying its ArgoCD PreSync hook and early sync-wave, and the
// dependency-blind exec probes.
export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-app-chart-template-green',
      description: 'Helm template renders the worker Deployment and the db-init PreSync Job with exec health probes.',
      kind: 'baseline',
      async run(repo: any) {
        const result = await repo.exec(
          'nix develop .#ci -c helm template go-consumer infra/root_chart --values infra/root_chart/values.lapras.yaml',
          { timeoutMs: 240000 },
        );
        const rendered = result.stdout ?? '';
        if (result.exitCode !== 0) {
          throw new Error(`app-chart-template failed on the healthy repo: ${result.stderr || rendered}`);
        }
        // Refuse an EMPTY render. `helm template` over a chart whose templates all
        // evaluate to nothing exits 0 and prints nothing; that is a vacuous pass.
        const documents = rendered.split(/^---$/m).filter(part => part.trim().length > 0);
        if (documents.length === 0) {
          throw new Error('app-chart-template exited 0 but rendered NO manifests');
        }
        const kinds = [...rendered.matchAll(/^kind:\s*(\S+)$/gm)].map(match => match[1]);
        if (kinds.length === 0) {
          throw new Error(`app-chart-template rendered ${documents.length} documents but no Kubernetes kinds`);
        }
        for (const required of ['Deployment', 'Job']) {
          if (!kinds.includes(required)) {
            throw new Error(`app-chart-template rendered no ${required}; kinds were ${kinds.join(', ')}`);
          }
        }
        if (!rendered.includes('argocd.argoproj.io/hook: PreSync')) {
          throw new Error('app-chart-template rendered a db-init Job without the ArgoCD PreSync hook');
        }
        // Read the sync-wave that sits ON the PreSync hook, not merely the first
        // wave anywhere in the render — the ExternalSecret also carries one (-2), so
        // an unanchored match would report a value belonging to another resource.
        const wave = rendered.match(
          /argocd\.argoproj\.io\/hook:\s*PreSync[\s\S]{0,600}?argocd\.argoproj\.io\/sync-wave:\s*"(-?\d+)"/,
        );
        if (!wave || Number(wave[1]) >= 0) {
          throw new Error(
            `app-chart-template rendered no EARLY sync-wave on the db-init PreSync hook (found ${wave ? wave[1] : 'none'}; it must be negative so db-init precedes the rollout)`,
          );
        }
        // Liveness AND readiness must BOTH be dependency-blind exec probes on the
        // binary's health subcommand (R20/DQ16), so both are counted, not just found.
        const execProbes = [...rendered.matchAll(/(liveness|readiness)Probe:\s*\n\s*exec:/g)].map(match => match[1]);
        for (const probe of ['liveness', 'readiness']) {
          if (!execProbes.includes(probe)) {
            throw new Error(
              `app-chart-template rendered no exec ${probe}Probe; exec probes present: ${execProbes.join(', ') || 'none'}`,
            );
          }
        }
        if (!/- health\b/.test(rendered)) {
          throw new Error('app-chart-template rendered exec probes that do not invoke the health subcommand');
        }
        // A worker serves no HTTP: a rendered Service would be a contract break.
        if (kinds.includes('Service')) {
          throw new Error('app-chart-template rendered a Service; the consumer serves no HTTP (R20)');
        }
      },
    },
  ],
};
