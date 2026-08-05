import { expectGreen, expectRedBecause } from './lib/helpers.ts';

const syntheticAuthor = 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.email GIT_CONFIG_VALUE_0=cyanprint@example.com';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-hook-releaser-commit-green',
      description: 'The installed commit-msg hook accepts a conventional subject.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          `message_path="$(mktemp)" && trap 'rm -f "$message_path"' EXIT && printf 'feat: valid commit message\\n' >"$message_path" && ${syntheticAuthor} nix develop .#ci -c pre-commit run a-releaser-commit --hook-stage commit-msg --commit-msg-filename "$message_path"`,
          'hook-releaser-commit',
        );
      },
    },
    {
      name: 'mutation-hook-releaser-commit-caught',
      description: 'A non-conventional subject turns the installed commit-msg hook red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await expectRedBecause(
          repo,
          `message_path="$(mktemp)" && trap 'rm -f "$message_path"' EXIT && printf 'not conventional\\n' >"$message_path" && ${syntheticAuthor} nix develop .#ci -c pre-commit run a-releaser-commit --hook-stage commit-msg --commit-msg-filename "$message_path"`,
          'hook-releaser-commit',
          ['- hook id: a-releaser-commit', 'CT1: header must match type(scope)!?: subject'],
        );
      },
    },
  ],
};
