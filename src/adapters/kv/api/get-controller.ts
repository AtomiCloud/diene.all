import type { Command } from 'commander';
import { NamespacedKeyValidationError } from '../../../lib/kv/slug';
import type { KvService } from '../../../lib/kv/service';
import type { ICliIo } from '../../terminal/console-io';
import type { IPrompt } from '../../terminal/prompt';
import { EXIT_ERROR, EXIT_OK } from '../../cli/exit-codes';

/** `get <namespace> [key]` — prompts for a missing key on a TTY, fails fast in CI so it never hangs. */
export class GetController {
  constructor(
    private readonly kv: KvService,
    private readonly io: ICliIo,
    private readonly prompt: IPrompt,
    private readonly interactive: boolean,
  ) {}

  register(program: Command): void {
    program
      .command('get')
      .description('read a value stored under a namespaced key')
      .argument('<namespace>', 'key namespace')
      .argument('[key]', 'key name (prompted for when omitted in an interactive terminal)')
      .action(async (namespace: string, key: string | undefined) => {
        this.io.setExitCode(await this.handle(namespace, key));
      });
  }

  async handle(namespace: string, key?: string): Promise<number> {
    let resolvedKey = key;
    if (resolvedKey === undefined) {
      if (!this.interactive) {
        this.io.error('missing argument: key (pass <key> or run in an interactive terminal)');
        return EXIT_ERROR;
      }
      resolvedKey = await this.prompt.ask('key');
    }

    try {
      const { composed, value } = await this.kv.getValue(namespace, resolvedKey);
      if (value === null) {
        this.io.warn(`not found: ${composed}`);
        return EXIT_ERROR;
      }
      this.io.success(value);
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
