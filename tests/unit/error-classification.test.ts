import { describe, it } from 'bun:test';
import should from 'should';
import type { Problem, ProblemCatalogEntry } from '@atomicloud/diene.problems';
import { classifyProblem } from '../../src/lib/error-classification';

const entry = (type: string, recoverable: boolean): ProblemCatalogEntry => ({
  id: type,
  type: `https://errors.test/${type}`,
  title: type,
  status: recoverable ? 409 : 500,
  recoverable,
  data: {},
  endpoints: [],
});

const problem = (type: string): Problem => ({
  type: `https://errors.test/${type}`,
  title: type,
  status: 500,
  data: {},
});

const catalog = [entry('conflict', true), entry('broken', false)];

describe('classifyProblem', () => {
  it.each([
    { type: 'conflict', expected: 'recoverable' },
    { type: 'broken', expected: 'fatal' },
    { type: 'never-seen', expected: 'uncatalogued' },
  ])('should classify $type as $expected', ({ type, expected }) => {
    // Arrange

    // Act
    const actual = classifyProblem(problem(type), catalog);

    // Assert
    should(actual.tier).equal(expected);
  });

  it('should carry the catalog entry for a catalogued problem', () => {
    // Arrange

    // Act
    const actual = classifyProblem(problem('conflict'), catalog);

    // Assert
    should(actual.entry?.recoverable).be.true();
  });

  it('should carry no entry for an uncatalogued problem', () => {
    // Arrange

    // Act
    const actual = classifyProblem(problem('mystery'), catalog);

    // Assert
    should(actual.entry).be.undefined();
  });
});
