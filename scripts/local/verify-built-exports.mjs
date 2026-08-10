import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

const runtimeMembers = [
  ['result', 'result'],
  ['interfaces', 'interfaces'],
  ['coreUtils', 'core-utils'],
  ['config', 'config'],
  ['problems', 'problems'],
  ['otel', 'otel'],
  ['auth', 'auth-engine'],
  ['api', 'api-engine'],
  ['standardConfig', 'standard-config'],
  ['frontendUtils', 'frontend-utils'],
];

const helperMembers = [
  ['result', 'result'],
  ['interfaces', 'interfaces'],
  ['config', 'config'],
  ['problems', 'problems'],
  ['otel', 'otel'],
  ['auth', 'auth-engine'],
  ['api', 'api-engine'],
  ['standardConfig', 'standard-config'],
  ['frontendUtils', 'frontend-utils'],
];

const compareNamespaces = (condition, actualRoot, members) => {
  for (const [namespace, member] of members) {
    const target =
      condition === 'import'
        ? import(`@atomicloud/diene.${member}${actualRoot.helper ? '/test-helper' : ''}`)
        : Promise.resolve(require(`@atomicloud/diene.${member}${actualRoot.helper ? '/test-helper' : ''}`));
    actualRoot.checks.push(
      target.then(expected => {
        const actual = actualRoot.module[namespace];
        const actualKeys = Object.keys(actual).sort();
        const expectedKeys = Object.keys(expected).sort();
        if (JSON.stringify(actualKeys) !== JSON.stringify(expectedKeys)) {
          throw new Error(`${condition} ${namespace} namespace keys differ from @atomicloud/diene.${member}`);
        }
        for (const key of expectedKeys) {
          if (actual[key] !== expected[key]) {
            throw new Error(`${condition} ${namespace}.${key} does not preserve member identity`);
          }
        }
      }),
    );
  }
};

const esmRuntime = { module: await import('../../dist/index.js'), helper: false, checks: [] };
const esmHelpers = { module: await import('../../dist/test-helper.js'), helper: true, checks: [] };
const cjsRuntime = { module: require('../../dist/index.cjs'), helper: false, checks: [] };
const cjsHelpers = { module: require('../../dist/test-helper.cjs'), helper: true, checks: [] };

compareNamespaces('import', esmRuntime, runtimeMembers);
compareNamespaces('import', esmHelpers, helperMembers);
compareNamespaces('require', cjsRuntime, runtimeMembers);
compareNamespaces('require', cjsHelpers, helperMembers);

await Promise.all([...esmRuntime.checks, ...esmHelpers.checks, ...cjsRuntime.checks, ...cjsHelpers.checks]);
