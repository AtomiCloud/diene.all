export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-http-auth-encryptor-green',
      description: 'Unit and integration baselines exercise the published clients and the symmetric encryption seam.',
      kind: 'baseline',
      async run(repo: any) {
        const unit = await repo.exec(
          "nix develop .#ci -c bash -lc './scripts/local/setup.sh && bun test --config=bunfig.unit.toml tests/unit/encryption.test.ts'",
          { timeoutMs: 600000 },
        );
        if (unit.exitCode !== 0) {
          throw new Error(`encryption unit baseline failed: ${unit.stderr || unit.stdout}`);
        }
        const int = await repo.exec(
          "nix develop .#ci -c bash -lc 'bun test --config=bunfig.int.toml tests/integration/published-clients.test.ts'",
          { timeoutMs: 900000 },
        );
        if (int.exitCode !== 0) {
          throw new Error(`published-clients integration baseline failed: ${int.stderr || int.stdout}`);
        }
      },
    },
  ],
};
