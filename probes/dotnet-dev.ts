import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-dev-green',
      description: 'The hot-reload development task starts the sample App.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#default -c dotnet build App/App.csproj -c Debug -m:1 /nodeReuse:false /p:UseSharedCompilation=false',
          'dotnet-dev-build',
          480000,
        );
        await expectGreen(
          repo,
          `nix develop .#default -c sh -lc '
            set -eu
            log="$(mktemp)"
            setsid pls dev >"$log" 2>&1 &
            pid=$!
            cleanup() {
              kill -TERM -"$pid" 2>/dev/null || true
              for attempt in $(seq 1 10); do
                if ! kill -0 -"$pid" 2>/dev/null; then
                  break
                fi
                sleep 1
              done
              kill -KILL -"$pid" 2>/dev/null || true
              wait "$pid" 2>/dev/null || true
              cat "$log"
              rm -f "$log"
            }
            trap cleanup EXIT
            for attempt in $(seq 1 240); do
              if rg -q "Success: infra presets composed, validated, and schema round-tripped" "$log"; then
                exit 0
              fi
              if ! kill -0 "$pid" 2>/dev/null; then
                set +e
                wait "$pid"
                code=$?
                set -e
                exit "$code"
              fi
              sleep 1
            done
            exit 124
          '`,
          'dotnet-base-probe-dev',
          360000,
        );
      },
    },
  ],
};
