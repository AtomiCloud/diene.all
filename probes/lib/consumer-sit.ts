// SIT journey harness for the go-consumer rows. Each row drives ONE journey
// through the COMPILED artifact (`dist/go-consumer`) against the full local
// dependency stack, exactly as `pls test:sit` does.
//
// Serialization, not uniqueness (PROBES §5 addendum): the local stack binds the
// FIXED host ports declared in `config/dev.yaml` (postgres 5432, redis 6379,
// minio 9000/9001, otlp 4318, clickhouse 8123, victoria-metrics 8428, grafana
// 3000), so two stacks cannot coexist and per-invocation uniqueness is genuinely
// impractical. The whole up -> journey -> down sequence therefore takes a
// host-level `mkdir` spinlock, and these rows declare a serialization
// requirement in their cost class. `mkdir` is atomic and portable where busybox
// `flock` is not; a lock whose recorded pid is gone is reclaimed rather than
// waited on forever.
//
// The script rides base64 on the command line and is decoded into a mktemp file
// UNDER $TMPDIR — never into the sandbox tree. A probe-authored file inside the
// repository would legitimately redden the gofumpt/shellcheck/prettier controls
// co-selected with this row, and a repo-local script would also be swept by the
// deadcode and executable-shells gates.
//
// The temp file is executed with stdin DETACHED (`bash "$f" </dev/null`) rather
// than piped into `bash` over stdin: `up.sh` runs `docker compose up` and
// `docker compose run`, both of which attach to stdin and would drain the
// remaining script bytes, silently swallowing the trailing journey line so the
// row exits 0 without ever asserting.
// GAP-5 SWEEP (PROBES Gap 5): this is the SECOND sandbox-constructing helper on
// this branch — `sandbox-script.ts` is the other — and the mitigation must cover
// EVERY one of them, not just the first. Both share one origin URL so the sweep
// cannot drift apart between them.
import { GAP5_PREAMBLE } from './sandbox-script';

const LOCK = '/tmp/diene-goconsumer-sit.lock.d';

// The SIT runner interface (controller-defined, 2026-07-26):
//
//   ./scripts/local/test-sit.sh <binary|parity> [journey-regex]
//
// `$1` selects the driver (`binary` = the compiled artifact only; `parity` =
// `e2e.RunParity`, compiled + in-process, refusing on disagreement) and sets
// `SIT_DRIVER`; `CLI_BIN` defaults to `dist/go-consumer`. `$2` is an optional
// journey selector passed straight to `go test -run <regex>` against
// `./tests/sit/...` — the Go analogue of bun-consumer's positional journey FILE,
// because Go selects tests by NAME, not by file.
//
// Every SIT row routes through this one function so the selector convention lives
// in exactly one place.
export function journeyCommand(journey: string): string {
  return `./scripts/local/test-sit.sh binary ${journey}`;
}

export function sitScript(journey: string): string {
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
${GAP5_PREAMBLE}./scripts/local/setup.sh
./scripts/local/build.sh
test -x dist/go-consumer || { echo "❌ compiled artifact dist/go-consumer is absent" >&2; exit 1; }
./scripts/local/up.sh
${journeyCommand(journey)}
`;
}

export function sitCommand(journey: string): string {
  const encoded = Buffer.from(sitScript(journey), 'utf8').toString('base64');
  return `nix develop .#ci -c bash -lc 'f="$(mktemp)"; echo ${encoded} | base64 -d >"$f"; bash "$f" </dev/null; r=$?; rm -f "$f"; exit $r'`;
}

// Assert on printed VALUES, not on a bare exit code.
//
// TWO VACUITY AXES, not one. A sabotage that reddens the row proves the mechanism
// enforces something; it does not prove the mechanism refuses to judge when its
// SUBJECT is missing. `go test -run <regex>` matching ZERO tests exits 0 and
// prints `ok ... no tests to run` — so a journey that was renamed, deleted, or
// never written would read as a clean pass. The healthy branch therefore requires
// the selected journey's NAME in the transcript and explicitly refuses the
// no-tests-to-run and no-test-files outcomes.
export async function runSitJourney(repo: any, journey: string, label: string, expectFail = false): Promise<void> {
  const result = await repo.exec(sitCommand(journey), { timeoutMs: 1800000 });
  const transcript = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;
  if (expectFail) {
    if (result.exitCode === 0) {
      throw new Error(`${label} stayed green after sabotage:\n${transcript}`);
    }
    return;
  }
  if (result.exitCode !== 0) {
    throw new Error(`${label} failed on the healthy repo:\n${transcript}`);
  }
  if (transcript.trim().length === 0) {
    throw new Error(`${label} exited 0 but printed nothing — the journey never ran`);
  }
  for (const vacuous of ['no tests to run', 'no test files', 'no packages to test']) {
    if (transcript.includes(vacuous)) {
      throw new Error(
        `${label} exited 0 but the runner reported ${JSON.stringify(vacuous)} — selector ${journey} matched no journey:\n${transcript}`,
      );
    }
  }
  if (!transcript.includes(journey)) {
    throw new Error(
      `${label} exited 0 without naming ${journey} in its transcript — refusing a pass that may have selected no journey:\n${transcript}`,
    );
  }
}
