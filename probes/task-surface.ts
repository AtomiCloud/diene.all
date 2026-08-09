// Serializes on the same host mkdir spinlock as the SIT rows: pls up/down binds
// the dev.yaml host ports, so concurrent stacks would collide (PROBES §5 addendum).
// The script rides base64 on the command line and is decoded under $TMPDIR so no
// probe-authored file lands in the sandbox tree to redden formatting controls.
// Running the file with stdin detached prevents docker compose from draining the
// trailing task assertions.
const LOCK = '/tmp/diene-bunconsumer-sit.lock.d';

const SCRIPT = `set -euo pipefail
while ! mkdir ${LOCK} 2>/dev/null; do
  pid="$(cat ${LOCK}/pid 2>/dev/null || true)"
  if [ -n "\${pid}" ] && ! kill -0 "\${pid}" 2>/dev/null; then rm -rf ${LOCK}; continue; fi
  sleep 5
done
echo $$ >${LOCK}/pid
cleanup() {
  pls down >/dev/null 2>&1 || true
  rm -rf ${LOCK}
}
trap cleanup EXIT
./scripts/local/setup.sh
pls up
pls run -- --help
pls preview -- --help
test -x scripts/local/dev.sh
`;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-task-surface-green',
      description:
        'The pls run/preview/up/down tasks execute their intended local operations; dev is exercised via its underlying script contract.',
      kind: 'baseline',
      async run(repo: any) {
        const encoded = Buffer.from(SCRIPT, 'utf8').toString('base64');
        const result = await repo.exec(
          `nix develop .#ci -c bash -lc 'f="$(mktemp)"; echo ${encoded} | base64 -d >"$f"; bash "$f" </dev/null; r=$?; rm -f "$f"; exit $r'`,
          { timeoutMs: 1800000 },
        );
        if (result.exitCode !== 0) {
          throw new Error(`task-surface failed on the healthy repo: ${result.stderr || result.stdout}`);
        }
      },
    },
  ],
};
