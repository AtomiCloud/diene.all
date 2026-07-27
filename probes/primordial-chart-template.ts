// COST CLASS: light (<30s) — one `helm template`, no cluster.
//
// Proven-only smoke: it asserts the rendered T3 CR SET as an artifact, not an exit
// code. The union `PlatformDependency` replaces the old per-kind postgres/redis/S3
// CRs and the message transport rides the existing kv/cache module, so there is NO
// transport CR — an appearance of one would be a contract break and is refused.
export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-primordial-chart-template-green',
      description:
        'Helm template renders the primordial T3 CR set: the PlatformDependency union CR and the Problem catalog.',
      kind: 'baseline',
      async run(repo: any) {
        const result = await repo.exec(
          'nix develop .#ci -c helm template go-consumer-primordial infra/primordial_chart --values infra/primordial_chart/values.lapras.yaml',
          { timeoutMs: 240000 },
        );
        const rendered = result.stdout ?? '';
        if (result.exitCode !== 0) {
          throw new Error(`primordial-chart-template failed on the healthy repo: ${result.stderr || rendered}`);
        }
        // Refuse an EMPTY render: every CR in this chart is conditional, so a values
        // mistake could switch the whole set off while `helm template` still exits 0.
        const documents = rendered.split(/^---$/m).filter(part => part.trim().length > 0);
        if (documents.length === 0) {
          throw new Error('primordial-chart-template exited 0 but rendered NO manifests');
        }
        const kinds = [...rendered.matchAll(/^kind:\s*(\S+)$/gm)].map(match => match[1]);
        if (kinds.length === 0) {
          throw new Error(`primordial-chart-template rendered ${documents.length} documents but no Kubernetes kinds`);
        }
        for (const required of ['PlatformDependency', 'Problem']) {
          if (!kinds.includes(required)) {
            throw new Error(`primordial-chart-template rendered no ${required} CR; kinds were ${kinds.join(', ')}`);
          }
        }
        // The union CRD replaced the per-kind dependency CRs; their return would mean
        // the chart drifted back to the abolished shape.
        for (const abolished of ['Postgres', 'Redis', 'S3Bucket', 'MessageTransport']) {
          if (kinds.includes(abolished)) {
            throw new Error(
              `primordial-chart-template rendered an abolished per-kind ${abolished} CR; PlatformDependency is the union CRD`,
            );
          }
        }
        // CloudflareDeploy and VirtualLandscapeService are omitted for this node: it
        // ships no edge assets and serves no v-landscape.
        for (const omitted of ['CloudflareDeploy', 'VirtualLandscapeService']) {
          if (kinds.includes(omitted)) {
            throw new Error(`primordial-chart-template rendered ${omitted}, which this node must omit`);
          }
        }
      },
    },
  ],
};
