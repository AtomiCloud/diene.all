// COST CLASS: heavy, SERIALIZED (see probes/lib/consumer-sit.ts).
//
// Why heavy is unavoidable: the mechanism is the COMPILED artifact's one-shot
// db-init dispatch driving the real dependency matrix — postgres/cache/kv/storage
// reachability, flagged bucket creation, migrations, and the idempotent seed. A
// lighter proxy cannot prove the built binary, given `db-init`, actually runs that
// matrix; unit fakes prove the orchestrator, not the dispatch.
import { runSitJourney } from './lib/consumer-sit.ts';

const JOURNEY = 'TestDBInitModeJourney';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-db-init-mode-sit-green',
      description: 'The compiled binary runs the one-shot postgres/cache/kv/storage db-init matrix.',
      kind: 'baseline',
      async run(repo: any) {
        await runSitJourney(repo, JOURNEY, 'db-init-mode-sit');
      },
    },
    {
      name: 'mutation-db-init-mode-sit-caught',
      description: 'Broken db-init dispatch turns the one-shot journey red.',
      kind: 'mutation',
      // Same-template collateral (R-E18), empirically observed live: `db-init` is the
      // FIRST step of every sibling journey, so disabling its dispatch reddens ALL four
      // other SIT rows. This ONE fault (S26) has total blast radius because db-init is the
      // shared bootstrap, not because the sabotage is multi-fault — R-E18 guard (b) is not
      // triggered (it cannot be narrowed: this is already the minimal db-init fault).
      // Because expectedImpact declares away EVERY co-selected control, NO clean control
      // survives, so this row's `caught` is only HALF-PROVEN (read-verdict.ts flags it).
      // The durable disposition is an R-E7 partition; that is not in this scope.
      expectedImpact: ['worker-mode-sit', 'db-init-idempotency-sit', 'message-journey-sit', 'otel-export-sit'],
      async run(repo: any) {
        // ONE fault: neuter the DB-INIT dispatch specifically, leaving worker and
        // health intact — this is a different mechanism from worker-mode dispatch and
        // therefore carries its own fault (S26). The target is found by PATTERN: the
        // composition-root function whose body orchestrates the initializer, located
        // by its `runDBInit` receiver signature rather than by a sample filename.
        const paths = (await repo.glob('cmd/**/*.go')).filter(path => !path.endsWith('_test.go')).sort();
        for (const path of paths) {
          const source = await repo.read(path);
          const signature = source.match(/func \(a \*Application\) runDBInit\([^)]*\)[^{]*\{\n/s);
          if (!signature) {
            continue;
          }
          const patched = source.replace(
            signature[0],
            `${signature[0]}\treturn errors.New("db-init mode dispatch disabled")\n`,
          );
          if (patched === source) {
            continue;
          }
          await repo.write(path, patched);
          await runSitJourney(repo, JOURNEY, 'db-init-mode-sit', true);
          return;
        }
        throw new Error('no structural db-init dispatch target found under cmd/');
      },
    },
  ],
};
