export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-commander-entry-green',
      description: 'One composition root selects the worker, db-init, and health subcommands.',
      kind: 'baseline',
      async run(repo: any) {
        const result = await repo.exec(
          "nix develop .#ci -c bash -lc './scripts/local/setup.sh && bun run ./src/index.ts --help'",
          { timeoutMs: 600000 },
        );
        if (result.exitCode !== 0) {
          throw new Error(`commander entry failed on the healthy repo: ${result.stderr || result.stdout}`);
        }
        for (const subcommand of ['worker', 'db-init', 'health']) {
          if (!result.stdout.includes(subcommand)) {
            throw new Error(`commander entry does not list the ${subcommand} subcommand`);
          }
        }
        if (/\bcron\b/i.test(result.stdout)) {
          throw new Error('commander entry exposes a cron surface');
        }
      },
    },
  ],
};
