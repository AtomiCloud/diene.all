import { toProblem } from '@atomicloud/diene.frontend-utils/content';
import { isLocalError } from '@atomicloud/diene.frontend-utils/content';
import { describe, it } from 'bun:test';
import should from 'should';

// The Problem boundary: NO exception ever reaches the screen raw. Two halves —
// the wrap (a thrown Error becomes a LocalError Problem carrying message and
// stack in `data`) and the mount (both error boundaries route through it).
//
// The mount half is asserted STATICALLY over the boundary sources rather than by
// rendering them: they are client components whose render path needs a DOM, and
// what matters is that the wrap is on the boundary's path at all. Removing the
// call is the sabotage this gate catches.

const BOUNDARIES = ['src/app/[locale]/error.tsx', 'src/app/global-error.tsx'] as const;

describe('toProblem', () => {
  it('should wrap a raw Error into a LocalError carrying message and stack', () => {
    // Arrange
    const error = new Error('the widget exploded');

    // Act
    const problem = toProblem(error);

    // Assert — RFC 9457 envelope with the technical detail in `data`, which is
    // what the default Problem view renders behind its details disclosure.
    should(isLocalError(problem)).equal(true);
    should(problem.title).be.a.String().and.not.empty();
    should(problem.status).be.a.Number();
    if (!isLocalError(problem)) throw new Error('expected a LocalError problem');
    should(problem.data.message).equal('the widget exploded');
    should(problem.data.stack).be.a.String().and.not.empty();
  });

  it('should pass an existing Problem through rather than double-wrapping it', () => {
    // Arrange — a Problem thrown from a catalogued failure keeps its identity, so
    // the boundary renders the real error instead of a generic local one.
    const original = { type: 'https://errors.test/known', title: 'Known', status: 409, data: { field: 'name' } };

    // Act
    const problem = toProblem(original);

    // Assert
    should(problem.type).equal('https://errors.test/known');
    should(isLocalError(problem)).equal(false);
  });
});

describe('error boundary wiring', () => {
  it.each(BOUNDARIES.map(path => ({ path })))('should wrap the caught error in $path', async ({ path }) => {
    // Arrange
    const source = await Bun.file(path).text();

    // Assert — the boundary converts before it renders; a boundary that rendered
    // `error` directly would put a raw stack on screen.
    should(source).match(/toProblem\(error\)/);
    should(source).match(/defaultProblemView\(problem\)/);
  });

  it.each(BOUNDARIES.map(path => ({ path })))('should still report the error to faro from $path', async ({ path }) => {
    // Arrange — rendering a Problem must not swallow the telemetry: the boundary
    // is the only place a client-side crash is observable from.
    const source = await Bun.file(path).text();

    // Assert
    should(source).match(/pushError\(error\)/);
  });
});
