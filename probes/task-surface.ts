// COST CLASS: heavy, SERIALIZED. `pls up` brings the whole local stack up, and it
// binds the FIXED host ports in `config/dev.yaml`, so this row takes the SAME host
// mkdir spinlock as the SIT rows (PROBES §5 addendum: declared serialization where
// per-invocation uniqueness is genuinely impractical). Heavy is unavoidable: the
// goal says these tasks must "execute their intended operations", and a task that is
// merely DECLARED in the Taskfile is exactly the looks-present-asserts-nothing case.
//
// Proven-only smoke (R7/M15/M16): standard task names, each resolving to a
// `scripts/local/*` script and actually running.
import { expectScriptGreen } from './lib/sandbox-script.ts';

const LOCK = '/tmp/diene-goconsumer-sit.lock.d';

const SCRIPT = `while ! mkdir ${LOCK} 2>/dev/null; do
  pid="$(cat ${LOCK}/pid 2>/dev/null || true)"
  if [ -n "\${pid}" ] && ! kill -0 "\${pid}" 2>/dev/null; then rm -rf ${LOCK}; continue; fi
  sleep 5
done
echo $$ >${LOCK}/pid
# PROBES §5 addendum: a gate creating named external resources must derive a UNIQUE
# per-invocation name. Without this the stack falls back to the FIXED compose.project
# in config/dev.yaml, so a leftover or concurrent stack under that name collides and
# 'pls up' fails on an already-bound container — which surfaces as a product failure.
# up.sh and down.sh both honour COMPOSE_PROJECT_NAME and enforce the diene-go-consumer
# prefix, so the suffix keeps the guard satisfied while isolating this invocation.
COMPOSE_PROJECT_NAME="diene-go-consumer-task-$$"
export COMPOSE_PROJECT_NAME
echo "compose project: \${COMPOSE_PROJECT_NAME}"
cleanup() {
  pls down >/dev/null 2>&1 || true
  rm -rf ${LOCK}
}
trap cleanup EXIT
./scripts/local/setup.sh

echo "=== every standard task resolves to a scripts/local script ==="
for task in dev run preview up down; do
  script="$(yq -r ".tasks.\\"\${task}\\".cmds[0]" Taskfile.yaml)"
  echo "\${task} -> \${script}"
  case "\${script}" in
    ./scripts/local/*) ;;
    *) echo "❌ task \${task} does not resolve to a scripts/local script (R7/M15/M16)" >&2; exit 1 ;;
  esac
  path="\${script%% *}"
  [ -x "\${path}" ] || { echo "❌ \${path} is missing or not executable" >&2; exit 1; }
done

echo "=== pls up ==="
pls up
running="$(docker compose --project-name "\${COMPOSE_PROJECT_NAME}" \\
  --file scripts/local/docker-compose.yaml ps --status running --quiet | wc -l | tr -d ' ')"
echo "\${running} local dependency containers running"
[ "\${running}" -eq 0 ] && { echo "❌ pls up started NO containers" >&2; exit 1; }

echo "=== pls run ==="
pls run -- --help

echo "=== pls preview ==="
pls preview -- --help
test -x dist/go-consumer || { echo "❌ pls preview produced no compiled artifact" >&2; exit 1; }

echo "=== pls down ==="
pls down
remaining="$(docker compose --project-name "\${COMPOSE_PROJECT_NAME}" \\
  --file scripts/local/docker-compose.yaml ps --status running --quiet | wc -l | tr -d ' ')"
echo "\${remaining} local dependency containers running after teardown"
[ "\${remaining}" -ne 0 ] && { echo "❌ pls down left \${remaining} containers running" >&2; exit 1; }

echo "=== pls down is error-safe when already down (M32) ==="
pls down
echo "✅ dev/run/preview/up/down executed their intended operations"
`;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-task-surface-green',
      description:
        'pls dev/run/preview/up/down resolve to scripts/local and execute their intended local operations; teardown is error-safe.',
      kind: 'baseline',
      async run(repo: any) {
        // Assert on printed VALUES: the container counts before and after teardown
        // are the evidence that `up` and `down` DID something. `dev` is asserted
        // through its script contract rather than executed, because it runs the
        // worker in the foreground until interrupted and has no terminating mode.
        await expectScriptGreen(
          repo,
          SCRIPT,
          'task-surface',
          [
            'local dependency containers running',
            '0 local dependency containers running after teardown',
            'dev -> ./scripts/local/dev.sh',
            'executed their intended operations',
          ],
          { timeoutMs: 1800000 },
        );
      },
    },
  ],
};
