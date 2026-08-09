// SIT journey harness: each row drives ONE journey file through the compiled
// binary against the full local dependency stack. Host ports come from
// config/dev.yaml, so stacks cannot coexist — the whole up→journey→down
// sequence serializes on a host-level mkdir spinlock (PROBES §5 addendum:
// declared serialization where per-invocation uniqueness is genuinely
// impractical; mkdir is atomic and portable where busybox flock is not).
//
// The script rides base64 on the command line and never lands in the sandbox
// tree: a probe-authored file inside the repo would legitimately redden the
// formatting/lint controls co-selected with this row. It is decoded into a
// mktemp file UNDER $TMPDIR (outside the repo) and executed with stdin detached
// (`bash "$f" </dev/null`) rather than piped into `bash` over stdin — see
// sitCommand for why: a stdin-piped script is silently truncated when a stage
// command (docker compose in up.sh) drains the shared stdin.
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
  // Materialise the journey to a temp file and run it with stdin detached rather
  // than piping the script into `bash` over stdin. Piping is fragile: the script
  // rides the same stdin the stage commands inherit, and `up.sh`'s `docker compose
  // up`/`run` attach to stdin and drain the remaining script bytes — silently
  // swallowing the trailing `bun test` line so the journey exits 0 without ever
  // asserting (whether the tail is lost depends on pipe buffering, so it surfaced
  // only on the slower proof droplet). Reading from a file with `</dev/null` keeps
  // the script whole and lets no stage consume it.
  return `nix develop .#ci -c bash -lc 'f="$(mktemp)"; echo ${encoded} | base64 -d >"$f"; bash "$f" </dev/null; r=$?; rm -f "$f"; exit $r'`;
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
