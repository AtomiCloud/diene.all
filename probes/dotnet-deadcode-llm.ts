import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-deadcode-llm-green',
      description: 'The broad LLM-oriented dead-code review emits findings without blocking.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          `nix develop .#ci -c sh -ec '
            output="$(task deadcode)"
            printf "%s\\n" "$output"
            [ "$(printf "%s\\n" "$output" | rg -c "^📊 Total: [0-9]+ issue\\(s\\)$")" -eq 2 ]
          '`,
          'dotnet-deadcode-llm',
          900000,
        );
      },
    },
  ],
};
