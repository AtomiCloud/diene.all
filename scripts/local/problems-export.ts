import { mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { dirname } from 'node:path';
import { Command } from 'commander';
import { emitDomainProblemResource } from '../../src/domain/problems';
import { loadApplicationConfig } from '../../src/config/load';

const root = resolve(import.meta.dir, '../..');
const program = new Command().option('--out <path>').option('--landscape <name>');
program.parse(Bun.argv);
const options = program.opts<{ landscape?: string; out?: string }>();
const config = await loadApplicationConfig({
  buildTimeEnv: {
    ATOMI_AUTH__LOGTO__APP_ID: 'problem-export',
    ATOMI_AUTH__LOGTO__APP_SECRET: 'problem-export',
    ATOMI_AUTH__LOGTO__MANAGEMENT__CLIENT_ID: 'problem-export',
    ATOMI_AUTH__LOGTO__MANAGEMENT__CLIENT_SECRET: 'problem-export',
  },
  configDir: resolve(root, 'config'),
  environment: process.env,
  landscape: options.landscape,
  prefix: 'ATOMI_',
});
const resource = emitDomainProblemResource(config.errorPortal, config.transport.stream, {
  landscape: config.app.landscape,
  platform: config.app.platform,
  service: config.app.service,
  version: config.errorPortal.version,
});
const output = `${JSON.stringify(resource, null, 2)}\n`;
if (options.out) {
  const outputPath = resolve(root, options.out);
  await mkdir(dirname(outputPath), { recursive: true });
  await Bun.write(outputPath, output);
} else process.stdout.write(output);
