import type { Command } from 'commander';
import { type ReleaseService, userMessage } from '../../lib/release/release-service';
import type { ICliIo } from '../terminal/console-io';
import { EXIT_ERROR, EXIT_SUCCESS } from './exit-codes';

export class ConventionsController {
  constructor(
    private readonly releases: ReleaseService,
    private readonly io: ICliIo,
  ) {}

  register(program: Command): void {
    program
      .command('conventions')
      .description('write the configured commit-conventions document')
      .action(() => this.handle());
  }

  async handle(): Promise<void> {
    try {
      const loaded = await this.releases.writeConventions();
      for (const warning of loaded.warnings) this.io.writeError(`warning: ${warning}\n`);
      this.io.write(`wrote ${loaded.config.conventions.path}\n`);
      this.io.setExitCode(EXIT_SUCCESS);
    } catch (error) {
      this.io.writeError(`${userMessage(error)}\n`);
      this.io.setExitCode(EXIT_ERROR);
    }
  }
}
