import { createGenericProblemRegistry, type Problem } from '@atomicloud/diene.problems';
import { buildProblemFromRegistry, expectProblem } from '@atomicloud/diene.problems/test-helper';

const registry = createGenericProblemRegistry({
  scheme: 'https',
  host: 'errors.example',
  landscape: 'pichu',
  platform: 'nitroso',
  service: 'zinc',
  module: 'api',
});
const problem: Problem = buildProblemFromRegistry(registry, 'unauthorized', { data: {} });
expectProblem(problem).toBe(registry.require('unauthorized'));

void problem;
