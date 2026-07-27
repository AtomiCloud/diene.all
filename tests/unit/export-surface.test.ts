import { describe, expect, test } from 'bun:test';
import * as apiMember from '@atomicloud/diene.api-engine';
import * as apiHelperMember from '@atomicloud/diene.api-engine/test-helper';
import * as authMember from '@atomicloud/diene.auth-engine';
import * as authHelperMember from '@atomicloud/diene.auth-engine/test-helper';
import * as configMember from '@atomicloud/diene.config';
import * as configHelperMember from '@atomicloud/diene.config/test-helper';
import * as coreUtilsMember from '@atomicloud/diene.core-utils';
import * as frontendUtilsMember from '@atomicloud/diene.frontend-utils';
import * as frontendUtilsHelperMember from '@atomicloud/diene.frontend-utils/test-helper';
import * as interfacesMember from '@atomicloud/diene.interfaces';
import * as interfacesHelperMember from '@atomicloud/diene.interfaces/test-helper';
import * as otelMember from '@atomicloud/diene.otel';
import * as otelHelperMember from '@atomicloud/diene.otel/test-helper';
import * as problemsMember from '@atomicloud/diene.problems';
import * as problemsHelperMember from '@atomicloud/diene.problems/test-helper';
import * as resultMember from '@atomicloud/diene.result';
import * as resultHelperMember from '@atomicloud/diene.result/test-helper';
import * as standardConfigMember from '@atomicloud/diene.standard-config';
import * as standardConfigHelperMember from '@atomicloud/diene.standard-config/test-helper';

import * as root from '../../src/index.ts';
import * as apiEntry from '../../src/entries/api.ts';
import * as apiHelperEntry from '../../src/entries/api-test-helper.ts';
import * as authEntry from '../../src/entries/auth.ts';
import * as authHelperEntry from '../../src/entries/auth-test-helper.ts';
import * as configEntry from '../../src/entries/config.ts';
import * as configHelperEntry from '../../src/entries/config-test-helper.ts';
import * as coreUtilsEntry from '../../src/entries/core-utils.ts';
import * as frontendUtilsEntry from '../../src/entries/frontend-utils.ts';
import * as frontendUtilsHelperEntry from '../../src/entries/frontend-utils-test-helper.ts';
import * as interfacesEntry from '../../src/entries/interfaces.ts';
import * as interfacesHelperEntry from '../../src/entries/interfaces-test-helper.ts';
import * as otelEntry from '../../src/entries/otel.ts';
import * as otelHelperEntry from '../../src/entries/otel-test-helper.ts';
import * as problemsEntry from '../../src/entries/problems.ts';
import * as problemsHelperEntry from '../../src/entries/problems-test-helper.ts';
import * as resultEntry from '../../src/entries/result.ts';
import * as resultHelperEntry from '../../src/entries/result-test-helper.ts';
import * as standardConfigEntry from '../../src/entries/standard-config.ts';
import * as standardConfigHelperEntry from '../../src/entries/standard-config-test-helper.ts';
import * as helperRoot from '../../src/test-helper/index.ts';

type RuntimeSurface = Readonly<Record<string, unknown>>;

const assertTransparentSurface = (actual: RuntimeSurface, member: RuntimeSurface): void => {
  expect(Object.keys(actual).sort()).toEqual(Object.keys(member).sort());
  for (const name of Object.keys(member)) expect(actual[name]).toBe(member[name]);
};

const runtimeEntries = [
  ['result', resultEntry, resultMember],
  ['interfaces', interfacesEntry, interfacesMember],
  ['core-utils', coreUtilsEntry, coreUtilsMember],
  ['config', configEntry, configMember],
  ['problems', problemsEntry, problemsMember],
  ['otel', otelEntry, otelMember],
  ['auth', authEntry, authMember],
  ['api', apiEntry, apiMember],
  ['standard-config', standardConfigEntry, standardConfigMember],
  ['frontend-utils', frontendUtilsEntry, frontendUtilsMember],
] as const;

const helperEntries = [
  ['result/test-helper', resultHelperEntry, resultHelperMember],
  ['interfaces/test-helper', interfacesHelperEntry, interfacesHelperMember],
  ['config/test-helper', configHelperEntry, configHelperMember],
  ['problems/test-helper', problemsHelperEntry, problemsHelperMember],
  ['otel/test-helper', otelHelperEntry, otelHelperMember],
  ['auth/test-helper', authHelperEntry, authHelperMember],
  ['api/test-helper', apiHelperEntry, apiHelperMember],
  ['standard-config/test-helper', standardConfigHelperEntry, standardConfigHelperMember],
  ['frontend-utils/test-helper', frontendUtilsHelperEntry, frontendUtilsHelperMember],
] as const;

describe('transparent member subpaths', () => {
  for (const [name, entry, member] of [...runtimeEntries, ...helperEntries]) {
    test(`${name} preserves every runtime binding by strict identity`, () => {
      assertTransparentSurface(entry, member);
    });
  }

  test('every entry source is an ESM export-star passthrough', async () => {
    const expected = new Map<string, string>([
      ...runtimeEntries.map(
        ([name]) => [name, `@atomicloud/diene.${name === 'auth' || name === 'api' ? `${name}-engine` : name}`] as const,
      ),
      ...helperEntries.map(([name]) => {
        const member = name.replace('/test-helper', '');
        const packageMember = member === 'auth' || member === 'api' ? `${member}-engine` : member;
        return [name.replace('/', '-'), `@atomicloud/diene.${packageMember}/test-helper`] as const;
      }),
    ]);

    for (const [file, target] of expected) {
      expect((await Bun.file(`src/entries/${file}.ts`).text()).trim()).toBe(`export * from '${target}';`);
    }
  });

  test('does not invent a core-utils helper subpath', async () => {
    const manifest = (await Bun.file('package.json').json()) as { exports: Record<string, unknown> };
    expect(manifest.exports['./core-utils/test-helper']).toBeUndefined();
    expect(await Bun.file('src/entries/core-utils-test-helper.ts').exists()).toBe(false);
  });
});

describe('curated root', () => {
  test('exposes frozen natural namespaces with member identities', () => {
    const namespaces = [
      [root.result, resultMember],
      [root.interfaces, interfacesMember],
      [root.coreUtils, coreUtilsMember],
      [root.config, configMember],
      [root.problems, problemsMember],
      [root.otel, otelMember],
      [root.auth, authMember],
      [root.api, apiMember],
      [root.standardConfig, standardConfigMember],
      [root.frontendUtils, frontendUtilsMember],
    ] as const;
    for (const [namespace, member] of namespaces) {
      expect(Object.isFrozen(namespace)).toBe(true);
      assertTransparentSurface(namespace as RuntimeSurface, member as RuntimeSurface);
    }
  });

  test('preserves curated high-traffic identities', () => {
    expect(root.Ok).toBe(resultMember.Ok);
    expect(root.Err).toBe(resultMember.Err);
    expect(root.Some).toBe(resultMember.Some);
    expect(root.None).toBe(resultMember.None);
    expect(root.ConfigRegistry).toBe(configMember.ConfigRegistry);
    expect(root.ProblemRegistry).toBe(problemsMember.ProblemRegistry);
    expect(root.initOtel).toBe(otelMember.initOtel);
  });
});

describe('bundled helper root', () => {
  test('exposes all nine real helper namespaces, frozen and identity-safe', () => {
    const namespaces = [
      [helperRoot.result, resultHelperMember],
      [helperRoot.interfaces, interfacesHelperMember],
      [helperRoot.config, configHelperMember],
      [helperRoot.problems, problemsHelperMember],
      [helperRoot.otel, otelHelperMember],
      [helperRoot.auth, authHelperMember],
      [helperRoot.api, apiHelperMember],
      [helperRoot.standardConfig, standardConfigHelperMember],
      [helperRoot.frontendUtils, frontendUtilsHelperMember],
    ] as const;
    for (const [namespace, member] of namespaces) {
      expect(Object.isFrozen(namespace)).toBe(true);
      assertTransparentSurface(namespace as RuntimeSurface, member as RuntimeSurface);
    }
  });
});
