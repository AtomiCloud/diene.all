import { createApiEngine, type ApiEngine } from '@atomicloud/diene.api-engine';
import type { Problem } from '@atomicloud/diene.problems';
import type { Result } from '@atomicloud/diene.result';
import type { IAuthStateRetriever } from '@atomicloud/diene.auth-engine';
import type { RootConfig } from '@/adapters/server-config';
import { buildProblemRegistry } from '@/adapters/problem-reporter/registry';
import { backendBindings } from './core';

/**
 * Assemble the api-engine from the registration point: every configured
 * backend resolves to a Result<T, Problem>-mapped client. DB clients and
 * engines are created per-request on Workers (caveat 7) — callers construct
 * this inside the request scope, never at module top level.
 */
export const buildApiEngine = (
  config: RootConfig,
  landscape: string,
  auth: IAuthStateRetriever,
): Result<ApiEngine, Problem> =>
  buildProblemRegistry(config.get('app'), config.get('seo'), landscape).andThen(problems =>
    createApiEngine({
      bindings: backendBindings(config, landscape, auth),
      problems: problems.api,
    }),
  );
