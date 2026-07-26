// SIT journey harness: each row drives ONE journey file through the compiled
// binary against the full local dependency stack. Host ports come from
// config/dev.yaml, so stacks cannot coexist — the whole up→journey→down
// sequence serializes on a host-level mkdir spinlock (PROBES §5 addendum:
// declared serialization where per-invocation uniqueness is genuinely
// impractical; mkdir is atomic and portable where busybox flock is not).
//
// The script rides base64 on the command line and never lands in the sandbox
// tree: a probe-authored file inside the repo would legitimately redden the
// formatting/lint controls co-selected with this row.
const LOCK = '/tmp/diene-bunconsumer-sit.lock.d';

export function sitScript(journeyFile: string): string {
  return `set -euo pipefail
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

export function sitCommand(journeyFile: string): string {
  const encoded = Buffer.from(sitScript(journeyFile), 'utf8').toString('base64');
  return `nix develop .#ci -c bash -lc 'echo ${encoded} | base64 -d | bash'`;
}

export async function runSitJourney(repo: any, journeyFile: string, label: string, expectFail = false): Promise<void> {
  const result = await repo.exec(sitCommand(journeyFile), { timeoutMs: 1800000 });
  if (!expectFail && result.exitCode !== 0) {
    throw new Error(`${label} failed on the healthy repo: ${result.stderr || result.stdout}`);
  }
  if (expectFail && result.exitCode === 0) {
    throw new Error(`${label} stayed green after sabotage`);
  }
}
