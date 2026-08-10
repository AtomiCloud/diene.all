import { stableConfig } from '@atomicloud/diene.core-utils';
import { z } from 'zod';
import type { ProblemRegistry } from './registry.js';
import type { JsonSchema, ProblemManifest, ProblemManifestEntry, RegisteredProblem } from './types.js';

export function problemDataJsonSchema(problem: RegisteredProblem): JsonSchema {
  return stableConfig(z.toJSONSchema(problem.dataSchema, { target: 'draft-7' })) as JsonSchema;
}

export function emitProblemManifest(registry: ProblemRegistry): ProblemManifest {
  const problems: ProblemManifestEntry[] = registry.list().map(problem => ({
    id: problem.id,
    type: problem.type,
    title: problem.title,
    status: problem.status,
    version: problem.version,
    data: problemDataJsonSchema(problem),
  }));
  const schemas = Object.fromEntries(problems.map(problem => [problem.type, problem.data]));
  return {
    problems,
    schemas: stableConfig(schemas) as Readonly<Record<string, JsonSchema>>,
  };
}
