export interface ICliIo {
  write(text: string): void;
  writeError(text: string): void;
  setExitCode(code: number): void;
}

export class ConsoleIo implements ICliIo {
  write(text: string): void {
    process.stdout.write(text);
  }

  writeError(text: string): void {
    process.stderr.write(text);
  }

  setExitCode(code: number): void {
    process.exitCode = code;
  }
}
