import { resolve } from 'node:path';
import { CommanderError } from 'commander';
import { buildWorld, createProgram, registerDomain } from '../../bin/releaser';
import type { ICliIo } from '../../src/adapters/terminal/console-io';

interface CliResult {
  readonly code: number;
  readonly out: string;
  readonly err: string;
}

interface CliDriver {
  run(args: readonly string[], cwd: string, env?: Readonly<Record<string, string>>): Promise<CliResult>;
}

class BinaryCliDriver implements CliDriver {
  constructor(private readonly binary: string) {}

  async run(args: readonly string[], cwd: string, env: Readonly<Record<string, string>> = {}): Promise<CliResult> {
    const processHandle = Bun.spawn([this.binary, ...args], {
      cwd,
      env: { ...process.env, ...env },
      stdout: 'pipe',
      stderr: 'pipe',
      timeout: 30_000,
      killSignal: 'SIGKILL',
    });
    const [out, err, code] = await Promise.all([
      new Response(processHandle.stdout).text(),
      new Response(processHandle.stderr).text(),
      processHandle.exited,
    ]);
    return { code, out, err };
  }
}

class InProcessCliDriver implements CliDriver {
  async run(args: readonly string[], cwd: string, env: Readonly<Record<string, string>> = {}): Promise<CliResult> {
    let out = '';
    let err = '';
    let code = 0;
    const io: ICliIo = {
      write: text => {
        out += text;
      },
      writeError: text => {
        err += text;
      },
      setExitCode: value => {
        code = value;
      },
    };
    const world = { ...buildWorld(cwd, { ...process.env, ...env }), io };
    const program = createProgram();
    registerDomain(program, world);
    program.configureOutput({
      writeOut: text => {
        out += text;
      },
      writeErr: text => {
        err += text;
      },
    });
    try {
      await program.parseAsync(['bun', 'releaser', ...args]);
    } catch (error) {
      if (error instanceof CommanderError) code = error.exitCode;
      else {
        err += `${error instanceof Error ? error.message : String(error)}\n`;
        code = 1;
      }
    }
    return { code, out, err };
  }
}

export function configuredDriver(): CliDriver {
  if (process.env.SIT_DRIVER === 'binary') {
    return new BinaryCliDriver(resolve(process.env.CLI_BIN ?? 'dist/bin/releaser-linux-x64-baseline'));
  }
  return new InProcessCliDriver();
}
