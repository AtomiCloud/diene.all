// SIT journey harness: each row drives ONE journey file through the compiled
// binary against the full local dependency stack. Host ports come from
// config/dev.yaml, so stacks cannot coexist — the whole up→journey→down
// sequence serializes on a host-level mkdir spinlock (PROBES §5 addendum:
// declared serialization where per-invocation uniqueness is genuinely
// impractical; mkdir is atomic and portable where busybox flock is not).
const LOCK = '/tmp/diene-bunconsumer-sit.lock.d';

export function sitScript(journeyFile: string): string {
  return `#!/usr/bin/env bash
set -euo pipefail
while ! mkdir ${LOCK} 2>/dev/null; do
  pid="$(cat ${LOCK}/pid 2>/dev/null || true)"
  if [ -n "\${pid}" ] && ! kill -0 "\${pid}" 2>/dev/null; then rm -rf ${LOCK}; continue; fi
  sleep 5
done
echo $$ >${LOCK}/pid
cleanup() {
  ./scripts/local/down.sh >/dev/null 2>&1 || true
  rm -rf ${LOCK}
}
trap cleanup EXIT
./scripts/local/setup.sh
./scripts/local/compile.sh
./scripts/local/up.sh
SIT_DRIVER=binary CLI_BIN=dist/bin/bun-consumer bun test --config=bunfig.sit.toml ${journeyFile}
`;
}

export async function runSitJourney(repo: any, journeyFile: string, label: string, expectFail = false): Promise<void> {
  await repo.write('.probe-sit-journey.sh', sitScript(journeyFile));
  const result = await repo.exec("nix develop .#ci -c bash -lc 'bash .probe-sit-journey.sh'", { timeoutMs: 1800000 });
  if (!expectFail && result.exitCode !== 0) {
    throw new Error(`${label} failed on the healthy repo: ${result.stderr || result.stdout}`);
  }
  if (expectFail && result.exitCode === 0) {
    throw new Error(`${label} stayed green after sabotage`);
  }
}
