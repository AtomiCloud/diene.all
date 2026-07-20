import { definePresence } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

export default definePresence({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'presence-dotnet-lib-probe-inventory',
    description: 'Every dotnet-lib catalog row has one class-bearing probe source.',
    async run(repo: any) {
      await expectGreen(
        repo,
        "nix develop .#ci -c bash -c 'jq -e '\''[.[] | select(.template == \"diene/dotnet-lib\") | .class] | all(. == \"gate\" or . == \"smoke\" or . == \"presence\")'\'' probes/features.json >/dev/null && test \"$(jq '\''[.[] | select(.template == \"diene/dotnet-lib\")] | length'\'' probes/features.json)\" -eq \"$(find probes -maxdepth 1 -type f -name '\''dotnet-lib-*.ts'\'' | wc -l)\"'",
        'dotnet-lib-probe-inventory',
      );
    },
  },
});
