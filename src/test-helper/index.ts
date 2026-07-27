import * as apiExports from '@atomicloud/diene.api-engine/test-helper';
import * as authExports from '@atomicloud/diene.auth-engine/test-helper';
import * as configExports from '@atomicloud/diene.config/test-helper';
import * as frontendUtilsExports from '@atomicloud/diene.frontend-utils/test-helper';
import * as interfacesExports from '@atomicloud/diene.interfaces/test-helper';
import * as otelExports from '@atomicloud/diene.otel/test-helper';
import * as problemsExports from '@atomicloud/diene.problems/test-helper';
import * as resultExports from '@atomicloud/diene.result/test-helper';
import * as standardConfigExports from '@atomicloud/diene.standard-config/test-helper';
import { freezeNamespace } from '../lib/namespace.js';

export const result = freezeNamespace(resultExports);
export const interfaces = freezeNamespace(interfacesExports);
export const config = freezeNamespace(configExports);
export const problems = freezeNamespace(problemsExports);
export const otel = freezeNamespace(otelExports);
export const auth = freezeNamespace(authExports);
export const api = freezeNamespace(apiExports);
export const standardConfig = freezeNamespace(standardConfigExports);
export const frontendUtils = freezeNamespace(frontendUtilsExports);

export * from './bruno.js';
export * from './garden.js';
