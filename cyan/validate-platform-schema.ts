import { readFileSync } from 'node:fs';
import Ajv2020 from 'ajv/dist/2020';
import addFormats from 'ajv-formats';
import { parse } from 'yaml';

const schemaPath = process.argv[2];
const manifestPath = process.argv[3];

if (!schemaPath || !manifestPath) {
  throw new Error('usage: bun validate-platform-schema.ts <schema.json> <manifest.yaml>');
}

const schema = JSON.parse(readFileSync(schemaPath, 'utf8'));
const manifest = parse(readFileSync(manifestPath, 'utf8'));
const ajv = new Ajv2020({ allErrors: true, strict: true });
addFormats(ajv);
const validate = ajv.compile(schema);

if (!validate(manifest)) {
  console.error(JSON.stringify(validate.errors, null, 2));
  process.exit(1);
}
