// COST CLASS: heavy, SERIALIZED (see probes/lib/consumer-sit.ts).
//
// Why heavy is unavoidable here: the mechanism under test is the COMPILED
// artifact's worker-mode dispatch against real dependencies. A lighter proxy —
// a unit test of the consume loop, or a `--help` parse — cannot prove that the
// built binary, given `worker`, actually enters the consume loop; that is exactly
// the regression class this row exists for. The row compiles once, brings the
// local stack up once, runs ONE journey, and tears down.
//
// SERIALIZATION rather than uniqueness: the stack binds the FIXED host ports in
// `config/dev.yaml`, so two stacks cannot coexist (PROBES §5 addendum permits a
// declared serialization requirement where per-invocation uniqueness is genuinely
// impractical). All SIT rows and `task-surface` share one host mkdir spinlock and
// must run at parallel 1 relative to each other.
import { runSitJourney } from './lib/consumer-sit.ts';

const JOURNEY = 'TestWorkerModeJourney';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-worker-mode-sit-green',
      description: 'The compiled binary runs the worker journey against the local dependency stack.',
      kind: 'baseline',
      async run(repo: any) {
        await runSitJourney(repo, JOURNEY, 'worker-mode-sit');
      },
    },
    {
      name: 'mutation-worker-mode-sit-caught',
      description: 'Broken worker-mode dispatch turns the worker journey red.',
      kind: 'mutation',
      // Same-template collateral (R-E18), empirically observed live against the SIT
      // stack: disabling worker dispatch reddens exactly the sibling rows that drive
      // `worker --once` — message-journey-sit and otel-export-sit. db-init-mode-sit and
      // db-init-idempotency-sit run only `db-init` and stay GREEN, so this row keeps two
      // clean controls and its `caught` is FULLY proven (not half-proven). Cross-template
      // impact is out of scope here (KNOWN-INSUFFICIENT via expectedImpact, R-E18a).
      expectedImpact: ['message-journey-sit', 'otel-export-sit'],
      async run(repo: any) {
        // ONE fault: neuter the composition root's WORKER dispatch specifically, so
        // the `worker` subcommand refuses to enter the consume loop while `db-init`
        // and `health` keep working. The target is found by PATTERN — the cobra
        // command whose `Use:` is `worker` — inside whichever composition-root file
        // declares it, selected by glob. It never names a sample file.
        const paths = (await repo.glob('cmd/**/*.go')).filter(path => !path.endsWith('_test.go')).sort();
        for (const path of paths) {
          const source = await repo.read(path);
          const match = source.match(/(\n\tcommand\.RunE = wrapRuntime\(func\(ctx context\.Context\) error \{\n)/);
          if (!match) {
            continue;
          }
          const patched = source.replace(
            match[1],
            `${match[1]}\t\treturn errors.New("worker mode dispatch disabled")\n`,
          );
          if (patched === source) {
            continue;
          }
          await repo.write(path, patched);
          await runSitJourney(repo, JOURNEY, 'worker-mode-sit', true);
          return;
        }
        throw new Error('no structural worker-mode dispatch target found under cmd/');
      },
    },
  ],
};
