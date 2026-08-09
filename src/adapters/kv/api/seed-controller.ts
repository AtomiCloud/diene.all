import type { Command } from 'commander';
import type { IProgressReporter } from '../../../lib/kv/interfaces';
import { NamespacedKeyValidationError } from '../../../lib/kv/slug';
import type { KvService } from '../../../lib/kv/service';
import type { ICliIo } from '../../terminal/console-io';
import { EXIT_ERROR, EXIT_OK } from '../../cli/exit-codes';
import { CountSchema, MAX_SEED_COUNT } from './validator';

/** `seed <namespace> <count>` — validates the req and routes to KvService.seed. */
export class SeedController {
  constructor(
    private readonly kv: KvService,
    private readonly io: ICliIo,
    private readonly progress: IProgressReporter,
  ) {}

  register(program: Command): void {
    program
      .command('seed')
      .description('write N sample entries under a namespace')
      .argument('<namespace>', 'key namespace')
      .argument('<count>', 'number of entries to write')
      .action(async (namespace: string, count: string) => {
        this.io.setExitCode(await this.handle(namespace, count));
      });
  }

  async handle(namespace: string, count: string): Promise<number> {
    const parsed = CountSchema.safeParse(count);
    if (!parsed.success) {
      this.io.error(`invalid input: count must be an integer between 1 and ${MAX_SEED_COUNT} (got "${count}")`);
      return EXIT_ERROR;
    }

    try {
      await this.kv.seed(namespace, parsed.data, this.progress);
      this.io.success(`seeded ${parsed.data} entries under "${namespace}"`);
      return EXIT_OK;
    } catch (error) {
      if (error instanceof NamespacedKeyValidationError) {
        this.io.error(`invalid input: ${error.message}`);
        return EXIT_ERROR;
      }
      this.io.error(`failed to reach the key-value backend: ${(error as Error).message}`);
      return EXIT_ERROR;
    }
  }
}
