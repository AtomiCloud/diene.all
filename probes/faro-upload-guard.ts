// Cost: light (<5s) — a static read of the build config, no shell.
//
// The source-map UPLOAD itself is design-time only (it needs a live Faro stack
// and a real API key), so it is deliberately not probed. What IS probed is the
// guard that keeps a credential-less build — every PR CI build — from mounting
// the uploader at all. Per the brief this check lives in the probe rather than in
// a repository script, because the guard is a property of next.config.ts alone.
const BOTH_CONDITIONS = [/faroBuild\.enabled/, /faroBuild\.key !== ''/];

const assertGuard = async (repo: any): Promise<boolean> => {
  const source = await repo.read('next.config.ts');
  // Both halves must appear in the SAME condition, so the conjunction is matched
  // as one expression rather than as two independent greps.
  return (
    /if \(faroBuild\.enabled && faroBuild\.key !== ''\) \{/.test(source) &&
    BOTH_CONDITIONS.every(pattern => pattern.test(source))
  );
};

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-faro-upload-guard-green',
      description:
        'The source-map uploader is mounted only when Faro is enabled AND a build key is present, so a no-credential build is a clean dry run.',
      kind: 'baseline',
      async run(repo: any) {
        if (!(await assertGuard(repo))) {
          throw new Error("next.config.ts does not guard the Faro uploader behind enabled && key !== ''");
        }
      },
    },
    {
      name: 'mutation-faro-upload-guard-caught',
      description: 'Removing the key-emptiness half of the guard turns the guard check red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // With `enabled` alone, PR CI mounts the uploader with a blank key: the
        // build either fails on an authentication error or silently uploads
        // nothing, and both read as an infrastructure flake rather than a bug.
        const path = 'next.config.ts';
        const source = await repo.read(path);
        await repo.write(
          path,
          source.replace("if (faroBuild.enabled && faroBuild.key !== '')", 'if (faroBuild.enabled)'),
        );
        if (await assertGuard(repo)) {
          throw new Error('faro-upload-guard stayed green after the key guard was removed');
        }
      },
    },
  ],
};
