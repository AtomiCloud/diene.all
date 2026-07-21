import { expectGreen, expectRed } from './helpers.ts';

type CommandGateOptions = {
  feature: string;
  description: string;
  command: string;
  file: string;
  find: string;
  replace: string;
};

export function commandGate(options: CommandGateOptions) {
  return {
    contractVersion: 1,
    sandbox: { snapshot: 'git', preserve: ['.direnv'] },
    probes: [
      {
        name: `baseline-${options.feature}-green`,
        description: options.description,
        kind: 'baseline',
        async run(repo: any) {
          await expectGreen(repo, options.command, options.feature);
        },
      },
      {
        name: `mutation-${options.feature}-caught`,
        description: `A focused sabotage must turn ${options.feature} red.`,
        kind: 'mutation',
        expectedImpact: [],
        async run(repo: any) {
          await repo.patch(options.file, { find: options.find, replace: options.replace });
          await expectRed(repo, options.command, options.feature);
        },
      },
    ],
  };
}

export function commandSmoke(feature: string, description: string, command: string) {
  return {
    contractVersion: 1,
    sandbox: { snapshot: 'git', preserve: ['.direnv'] },
    probes: [
      {
        name: `baseline-${feature}-green`,
        description,
        kind: 'baseline',
        async run(repo: any) {
          const result = await repo.exec(command, { timeoutMs: 900000 });
          if (result.exitCode !== 0) {
            throw new Error(`${feature} failed: ${result.stderr || result.stdout}`);
          }
        },
      },
    ],
  };
}
