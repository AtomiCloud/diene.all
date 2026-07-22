import type { Command } from 'commander';
import type { CommitLinter } from '../../lib/commits/linter';
import { userMessage } from '../../lib/release/release-service';
import type { IConfigRepository, IFileSystem } from '../../lib/release/ports';
import type { ICliIo } from '../terminal/console-io';
import { EXIT_ERROR, EXIT_SUCCESS } from './exit-codes';

export class LintCommitController {
  constructor(
    private readonly configs: IConfigRepository,
    private readonly files: IFileSystem,
    private readonly linter: CommitLinter,
    private readonly io: ICliIo,
  ) {}

  register(program: Command): void {
    program
      .command('lint-commit')
      .description('validate a commit message')
      .argument('<msgfile>', 'commit-message file')
      .option('-c, --config <path>', 'release configuration path', 'atomi_release.yaml')
      .action((msgfile: string, options: { config: string }) => this.handle(msgfile, options.config));
  }

  async handle(msgfile: string, configPath: string): Promise<void> {
    try {
      const loaded = await this.configs.load(configPath);
      const diagnostics = this.linter.lint(await this.files.readText(msgfile), loaded.config);
      if (diagnostics.length > 0) {
        for (const item of diagnostics) this.io.writeError(`${msgfile}:${item.line}:${item.rule}: ${item.message}\n`);
        this.io.setExitCode(EXIT_ERROR);
        return;
      }
      this.io.setExitCode(EXIT_SUCCESS);
    } catch (error) {
      this.io.writeError(`${msgfile}:1:config: ${userMessage(error)}\n`);
      this.io.setExitCode(EXIT_ERROR);
    }
  }
}
