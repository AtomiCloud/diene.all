import type { Command } from 'commander';
import { type ReleaseService, userMessage } from '../../lib/release/release-service';
import type { ICliIo } from '../terminal/console-io';
import { EXIT_ERROR, EXIT_NO_RELEASE, EXIT_SUCCESS } from './exit-codes';

export class NextController {
  constructor(
    private readonly releases: ReleaseService,
    private readonly io: ICliIo,
  ) {}

  register(program: Command): void {
    program
      .command('next')
      .description('print the next release version')
      .action(() => this.handle());
  }

  async handle(): Promise<void> {
    try {
      const preview = await this.releases.preview();
      if (preview === null) {
        this.io.writeError('no release necessary\n');
        this.io.setExitCode(EXIT_NO_RELEASE);
        return;
      }
      this.io.write(`${preview.version}\n`);
      this.io.setExitCode(EXIT_SUCCESS);
    } catch (error) {
      this.io.writeError(`${userMessage(error)}\n`);
      this.io.setExitCode(EXIT_ERROR);
    }
  }
}
