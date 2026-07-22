import type { Command } from 'commander';
import { userMessage, type ReleaseService } from '../../lib/release/release-service';
import type { ICliIo } from '../terminal/console-io';
import { EXIT_ERROR, EXIT_SUCCESS } from './exit-codes';

export class ChangelogController {
  constructor(
    private readonly releases: ReleaseService,
    private readonly io: ICliIo,
  ) {}

  register(program: Command): void {
    program
      .command('changelog')
      .description('print pending release notes')
      .action(() => this.handle());
  }

  async handle(): Promise<void> {
    try {
      const preview = await this.releases.preview();
      if (preview !== null) this.io.write(preview.notes);
      this.io.setExitCode(EXIT_SUCCESS);
    } catch (error) {
      this.io.writeError(`${userMessage(error)}\n`);
      this.io.setExitCode(EXIT_ERROR);
    }
  }
}
