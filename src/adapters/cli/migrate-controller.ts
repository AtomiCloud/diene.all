import type { Command } from 'commander';
import type { MigrationService } from '../../lib/migration/migration-service';
import { userMessage } from '../../lib/release/release-service';
import type { ICliIo } from '../terminal/console-io';
import { EXIT_ERROR, EXIT_SUCCESS } from './exit-codes';

export class MigrateController {
  constructor(
    private readonly migration: MigrationService,
    private readonly io: ICliIo,
  ) {}

  register(program: Command): void {
    program
      .command('migrate')
      .description('rewrite a legacy configuration as schemaVersion 2')
      .action(() => this.handle());
  }

  async handle(): Promise<void> {
    try {
      this.io.write((await this.migration.migrate()).output);
      this.io.setExitCode(EXIT_SUCCESS);
    } catch (error) {
      this.io.writeError(`${userMessage(error)}\n`);
      this.io.setExitCode(EXIT_ERROR);
    }
  }
}
