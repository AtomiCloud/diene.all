import type { Command } from 'commander';
import { NamespacedKeyValidationError } from '../../../lib/kv/slug';
import type { KvService } from '../../../lib/kv/service';
import type { ICliIo } from '../../terminal/console-io';
import { EXIT_ERROR, EXIT_OK } from '../../cli/exit-codes';
import { MAX_TTL_SECONDS, TtlSchema } from './validator';

/** `set <namespace> <key> <value> [--ttl <seconds>]` — validates the req and routes to KvService. */
export class SetController {
  constructor(
    private readonly kv: KvService,
    private readonly io: ICliIo,
  ) {}

  register(program: Command): void {
    program
      .command('set')
      .description('store a value under a namespaced key')
      .argument('<namespace>', 'key namespace')
      .argument('<key>', 'key name')
      .argument('<value>', 'value to store')
      .option('--ttl <seconds>', 'expire the entry after the given number of seconds')
      .action(async (namespace: string, key: string, value: string, options: { ttl?: string }) => {
        this.io.setExitCode(await this.handle(namespace, key, value, options.ttl));
      });
  }

  async handle(namespace: string, key: string, value: string, ttl?: string): Promise<number> {
    let ttlSeconds: number | undefined;
    if (ttl !== undefined) {
      const parsed = TtlSchema.safeParse(ttl);
      if (!parsed.success) {
        this.io.error(
          `invalid input: --ttl must be a positive integer of at most ${MAX_TTL_SECONDS} seconds (got "${ttl}")`,
        );
        return EXIT_ERROR;
      }
      ttlSeconds = parsed.data;
    }

    try {
      const composed = await this.kv.setValue(namespace, key, value, ttlSeconds);
      const ttlNote = ttlSeconds === undefined ? '' : ` (expires in ${ttlSeconds}s)`;
      this.io.success(`set ${composed} = ${value}${ttlNote}`);
      return EXIT_OK;
    } catch (error) {
      if (error instanceof NamespacedKeyValidationError) {
        this.io.error(`invalid input: ${error.message}`);
        return EXIT_ERROR;
      }
      this.io.error(`failed to reach key-value backend: ${(error as Error).message}`);
      return EXIT_ERROR;
    }
  }
}
