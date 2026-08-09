import { resolve } from 'node:path';
import { generateJsonSchema } from '@atomicloud/diene.e2e/config';
import { z } from 'zod';
import { applicationRegistry } from '../../src/config/schema';

const argumentsSchema = z.object({ out: z.string().min(1) });
const outIndex = Bun.argv.indexOf('--out');
const arguments_ = argumentsSchema.parse({
  out: outIndex >= 0 ? Bun.argv[outIndex + 1] : resolve(import.meta.dir, '../../schemas/bun-consumer.schema.json'),
});
const schema = generateJsonSchema(applicationRegistry, {
  id: 'https://schemas.atomi.cloud/diene/bun-consumer.schema.json',
});
await Bun.write(arguments_.out, `${JSON.stringify(schema, null, 2)}\n`);
