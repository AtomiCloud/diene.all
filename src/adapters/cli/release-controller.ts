import type { Command } from 'commander';
import { type ReleaseService, userMessage } from '../../lib/release/release-service';
import type { ICliIo } from '../terminal/console-io';
import { EXIT_ERROR, EXIT_SUCCESS } from './exit-codes';

export class ReleaseController {
  constructor(
    private readonly releases: ReleaseService,
    private readonly io: ICliIo,
  ) {}

  register(program: Command): void {
    program
      .command('release')
      .description('calculate and perform a release')
      .option('--dry-run', 'print the next version and notes without side effects')
      .option('-c, --config <path>', 'release configuration path', 'atomi_release.yaml')
      .action((options: { dryRun?: boolean; config: string }) => this.handle(options.dryRun === true, options.config));
  }

  async handle(dryRun: boolean, configPath: string): Promise<void> {
    try {
      const preview = await this.releases.release(configPath, dryRun);
      if (preview === null) {
        this.io.write('no release necessary\n');
      } else {
        for (const warning of preview.warnings) this.io.writeError(`warning: ${warning}\n`);
        this.io.write(dryRun ? `${preview.version}\n\n${preview.notes}` : `released ${preview.version}\n`);
      }
      this.io.setExitCode(EXIT_SUCCESS);
    } catch (error) {
      this.io.writeError(`${userMessage(error)}\n`);
      this.io.setExitCode(EXIT_ERROR);
    }
  }
}
