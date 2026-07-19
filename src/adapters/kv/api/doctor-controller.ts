import type { Command } from 'commander';
import type { DoctorService } from '../../../lib/kv/doctor-service';
import type { ICliIo } from '../../terminal/console-io';
import type { ISpinner } from '../../terminal/spinner';
import { EXIT_ERROR, EXIT_OK } from '../../cli/exit-codes';

/** `doctor` — routes to DoctorService and renders spinner/platform feedback. */
export class DoctorController {
  constructor(
    private readonly doctor: DoctorService,
    private readonly io: ICliIo,
    private readonly spinner: ISpinner,
  ) {}

  register(program: Command): void {
    program
      .command('doctor')
      .description('check the key-value backend and report the platform')
      .action(async () => {
        this.io.setExitCode(await this.handle());
      });
  }

  async handle(): Promise<number> {
    try {
      this.io.success(`platform: ${await this.doctor.platform()}`);
    } catch (error) {
      this.io.warn(`could not detect platform: ${(error as Error).message}`);
    }

    this.spinner.start('checking key-value backend ...');
    try {
      if (!(await this.doctor.probeBackend())) {
        this.spinner.fail('key-value backend returned an unexpected value');
        return EXIT_ERROR;
      }
      this.spinner.succeed('key-value backend reachable');
      return EXIT_OK;
    } catch (error) {
      this.spinner.fail(`key-value backend unreachable: ${(error as Error).message}`);
      return EXIT_ERROR;
    }
  }
}
