import { expectGreen, expectRed } from './lib/helpers.ts';

const syntheticAuthor = 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.email GIT_CONFIG_VALUE_0=cyanprint@example.com';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-hook-gitlint-green',
      description: 'The installed commit-msg hook accepts a conventional subject.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          `message_path="$(mktemp)" && trap 'rm -f "$message_path"' EXIT && printf 'feat: valid commit message\n' >"$message_path" && ${syntheticAuthor} nix develop .#ci -c pre-commit run gitlint --hook-stage commit-msg --commit-msg-filename "$message_path"`,
          'hook-gitlint',
        );
      },
    },
    {
      name: 'mutation-hook-gitlint-caught',
      description: 'A non-conventional subject turns the installed commit-msg hook red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await expectRed(
          repo,
          `message_path="$(mktemp)" && trap 'rm -f "$message_path"' EXIT && printf 'not conventional\n' >"$message_path" && ${syntheticAuthor} nix develop .#ci -c pre-commit run gitlint --hook-stage commit-msg --commit-msg-filename "$message_path"`,
          'hook-gitlint',
        );
      },
    },
  ],
};
