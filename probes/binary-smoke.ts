import { expectGreen, expectRedBecause } from './lib/helpers.ts';

const declarationFiles = 'nix/packages.nix nix/env.nix';

// Text assertion on the declaration, not `command -v`: the shell inherits caller PATH.
const retired = [
  { binary: 'pls', reason: 'task (go-task) is the only task runner' },
  { binary: 'sg', reason: 'the releaser replaced it, there is no gitlint bootstrap' },
];

const absenceCommand = (binary: string) =>
  `nix develop .#default -c bash -c 'if rg -q "\\b${binary}\\b" ${declarationFiles}; then echo "${binary} is back in the nix inventory" >&2; exit 1; fi; echo "${binary} is absent from the nix inventory"'`;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      // This node keeps scripts/validate/binary-smoke.sh rather than taking the
      // parent's `dlint toolchain-smoke`: the parent's binary list is the agnostic
      // one and does not carry dotnet, dotnetlint or dn-inspect. The script asserts
      // PATH resolution AND a real invocation for every declared binary, which the
      // parent splits across two arms.
      name: 'baseline-binary-smoke-resolves',
      description: 'Every binary the workspace declares for the default shell resolves in it and answers a real call.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#default -c ./scripts/validate/binary-smoke.sh', 'binary-smoke', 600000);
      },
    },
    ...retired.flatMap(({ binary, reason }) => [
      {
        name: `baseline-binary-smoke-${binary}-absent`,
        description: `${binary} is not declared in the nix inventory: ${reason}.`,
        kind: 'baseline' as const,
        async run(repo: any) {
          await expectGreen(repo, absenceCommand(binary), 'binary-smoke');
        },
      },
      {
        name: `mutation-binary-smoke-${binary}-redeclared-caught`,
        description: `Re-declaring ${binary} in the nix inventory must turn the absence assertion red.`,
        kind: 'mutation' as const,
        expectedImpact: [],
        // Injected into the package set, not into an env group: an env group naming a
        // package the set does not carry breaks `nix develop` at EVALUATION, so the
        // arm would go red without ever reaching the assertion.
        async run(repo: any) {
          const source = await repo.read('nix/packages.nix');
          const anchor = '          atomiutils\n';
          if (!source.includes(anchor)) {
            throw new Error(`could not find the registry inherit anchor in nix/packages.nix`);
          }
          await repo.write('nix/packages.nix', source.replace(anchor, `${anchor}          ${binary}\n`));
          await expectRedBecause(repo, absenceCommand(binary), 'binary-smoke', [
            `${binary} is back in the nix inventory`,
          ]);
        },
      },
    ]),
  ],
};
