import * as apiExports from '@atomicloud/diene.api-engine';
import * as authExports from '@atomicloud/diene.auth-engine';
import * as configExports from '@atomicloud/diene.config';
import * as coreUtilsExports from '@atomicloud/diene.core-utils';
import * as frontendUtilsExports from '@atomicloud/diene.frontend-utils';
import * as interfacesExports from '@atomicloud/diene.interfaces';
import * as otelExports from '@atomicloud/diene.otel';
import * as problemsExports from '@atomicloud/diene.problems';
import * as resultExports from '@atomicloud/diene.result';
import * as standardConfigExports from '@atomicloud/diene.standard-config';
import { freezeNamespace } from './lib/namespace.js';

/** Frozen runtime namespaces for the complete ten-member Bun train. */
export const result = freezeNamespace(resultExports);
export const interfaces = freezeNamespace(interfacesExports);
export const coreUtils = freezeNamespace(coreUtilsExports);
export const config = freezeNamespace(configExports);
export const problems = freezeNamespace(problemsExports);
export const otel = freezeNamespace(otelExports);
export const auth = freezeNamespace(authExports);
export const api = freezeNamespace(apiExports);
export const standardConfig = freezeNamespace(standardConfigExports);
export const frontendUtils = freezeNamespace(frontendUtilsExports);

// Curated high-traffic identities. Broader APIs stay collision-free behind the
// namespaces above or their transparent public subpaths.
export { Err, None, Ok, Opt, Res, Some } from '@atomicloud/diene.result';
export type { Option, Result } from '@atomicloud/diene.result';
export { ConfigRegistry, loadConfig } from '@atomicloud/diene.config';
export type { Config } from '@atomicloud/diene.config';
export { createProblem, isProblem, ProblemRegistry } from '@atomicloud/diene.problems';
export type { Problem } from '@atomicloud/diene.problems';
export { initOtel } from '@atomicloud/diene.otel';
export type { OtelInitOptions, OtelRuntime } from '@atomicloud/diene.otel';
