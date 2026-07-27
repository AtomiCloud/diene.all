// COST CLASS: medium (<3min) — one compile plus three no-dependency invocations.
//
// Proven-only smoke. The mechanism is M35: exactly ONE composition root, and that
// one root dispatches `worker`, `db-init`, and `health`. It is exercised through the
// COMPILED artifact, because a `go run` of the package would not prove the shipped
// binary's dispatch — and the image's entrypoint is the binary.
//
// Naming note: bun-consumer's row is `commander-entry`; this one is `cmd-entry`
// because the goal names the feature "cmd entry" and Go dispatch is cobra.
import { expectScriptGreen } from './lib/sandbox-script.ts';

// `--help` on each subcommand parses that subcommand's own flag set without
// loading configuration or dialling a dependency, so this stays stack-free.
const SCRIPT = `./scripts/local/setup.sh
./scripts/local/build.sh
test -x dist/go-consumer || { echo "❌ compiled artifact dist/go-consumer is absent" >&2; exit 1; }
roots="$(go list -f '{{if eq .Name "main"}}{{.ImportPath}}{{end}}' ./... | grep . || true)"
count="$(printf '%s\\n' "\${roots}" | grep -c . || true)"
echo "\${count} main packages: \${roots}"
[ "\${count}" -ne 1 ] && { echo "❌ M35 requires exactly ONE entry point, found \${count}" >&2; exit 1; }
echo "=== root dispatch ==="
./dist/go-consumer --help
for sub in worker db-init health; do
  echo "=== subcommand \${sub} ==="
  ./dist/go-consumer "\${sub}" --help
done
echo "✅ one composition root dispatches worker, db-init, and health"
`;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-cmd-entry-green',
      description: 'Exactly one composition root selects the worker, db-init, and health subcommands.',
      kind: 'baseline',
      async run(repo: any) {
        const result = await expectScriptGreen(
          repo,
          SCRIPT,
          'cmd-entry',
          ['1 main packages', 'Available Commands', 'one composition root dispatches'],
          { timeoutMs: 900000 },
        );
        // Assert on the printed VALUES of the dispatch table, not merely on exit 0:
        // every required subcommand must be LISTED by the root, and each must have
        // answered its own `--help`.
        for (const subcommand of ['worker', 'db-init', 'health']) {
          if (!result.transcript.includes(`=== subcommand ${subcommand} ===`)) {
            throw new Error(`cmd-entry never invoked the ${subcommand} subcommand`);
          }
          if (!new RegExp(`^\\s+${subcommand}\\s+\\S`, 'm').test(result.transcript)) {
            throw new Error(`cmd-entry root help does not list the ${subcommand} subcommand`);
          }
        }
        // NO cron surface anywhere (R20: one-shot Jobs are the only sanctioned job
        // shape), and no HTTP server surface — this template serves no requests.
        for (const forbidden of ['cron', 'serve', 'listen']) {
          if (new RegExp(`^\\s+${forbidden}\\s+\\S`, 'm').test(result.transcript)) {
            throw new Error(`cmd-entry exposes a forbidden ${forbidden} surface`);
          }
        }
      },
    },
  ],
};
