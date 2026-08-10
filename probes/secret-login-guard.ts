export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      // `scripts/local/secrets.sh` has exactly one non-interactive path, and this is it.
      // The login path needs a terminal and a real Infisical instance, so no arm can
      // exercise it; the argument guard can be, and it is the part of the script this
      // workspace actually promises - that the removed `fetch` and `scan` actions refuse
      // loudly rather than being read as a request to log in.
      //
      // Deliberately NOT run inside a development shell: the guard fires before anything
      // reaches the `infisical` binary, so entering a shell would only add a dependency
      // the assertion does not have.
      name: 'baseline-secret-login-guard-refuses-actions',
      description: 'The secrets helper refuses the removed fetch/scan actions and names the reason.',
      kind: 'baseline',
      async run(repo: any) {
        for (const stale of ['fetch', 'scan']) {
          const result = await repo.exec(`./scripts/local/secrets.sh ${stale}`);
          if (result.exitCode === 0) {
            throw new Error(`secrets.sh accepted the removed '${stale}' action`);
          }
          const output = `${result.stdout}${result.stderr}`;
          // The exit code alone would also be produced by a script that simply failed to
          // start, so the refusal has to name both itself and the argument it rejected.
          if (!output.includes('secrets.sh takes no arguments') || !output.includes(`'${stale}' is not an action`)) {
            throw new Error(`secrets.sh refused '${stale}' without saying why: ${output}`);
          }
        }
      },
    },
  ],
};
