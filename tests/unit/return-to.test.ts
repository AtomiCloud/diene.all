import { describe, it } from 'bun:test';
import should from 'should';
import { buildLoginRedirect, continueTo, resolveReturnTo } from '../../src/lib/redirect/return-to';
import { authProblems } from './support';

const OPEN_REDIRECTS = [
  '',
  'https://evil.invalid/x',
  '//evil.invalid/x',
  '/\\evil.invalid/x',
  'javascript:alert(1)',
  '/ok\rno',
  '/ok\nno',
];

describe('returnTo', () => {
  it('round-trips the full path, query, and fragment byte-exactly', async () => {
    // Arrange
    const target = '/orders/42?filter=a%20b&repeat=1&repeat=2#receipt';

    // Act
    const redirect = buildLoginRedirect('/login', target);
    const encoded = new URL(`https://app.invalid${redirect}`).searchParams.get('returnTo');
    const resolved = await resolveReturnTo(encoded as string).unwrap();

    // Assert
    should(redirect).equal('/login?returnTo=%2Forders%2F42%3Ffilter%3Da%2520b%26repeat%3D1%26repeat%3D2%23receipt');
    should(resolved).equal(target);
    should(continueTo(target)).equal(target);
  });

  it('preserves an existing login query and fragment', () => {
    // Arrange
    const loginPath = '/login?mode=signup#form';

    // Act
    const redirect = buildLoginRedirect(loginPath, '/private?a=1');

    // Assert
    should(redirect).equal('/login?mode=signup&returnTo=%2Fprivate%3Fa%3D1#form');
  });

  it('is total for malformed Unicode input and encodes its well-formed replacement', () => {
    // Arrange
    const unpairedSurrogate = '/private/\uD800';

    // Act
    const actual = buildLoginRedirect('/login', unpairedSurrogate);

    // Assert
    should(actual).equal('/login?returnTo=%2Fprivate%2F%EF%BF%BD');
  });

  for (const raw of OPEN_REDIRECTS) {
    it(`rejects open-redirect input ${JSON.stringify(raw)} with a problem-typed Result`, async () => {
      // Arrange
      const { problems } = authProblems();

      // Act
      const rejected = resolveReturnTo(raw, problems);
      const problem = await rejected.unwrapErr();

      // Assert
      should(await rejected.isErr()).be.true();
      should(problem.type).equal(problems.InvalidReturnTo.type);
      should(continueTo(raw, '/safe')).equal('/safe');
    });
  }

  it('provides an unbound Problem when a registry is intentionally omitted', async () => {
    // Arrange
    const raw = '//evil.invalid';

    // Act
    const problem = await resolveReturnTo(raw).unwrapErr();

    // Assert
    should(problem.type).equal('about:blank');
    should(problem.status).equal(400);
  });

  it('falls back to root when both the continuation and caller fallback are unsafe', () => {
    // Arrange
    const continuation = '//evil.invalid';
    const fallback = 'https://fallback.invalid';

    // Act
    const actual = continueTo(continuation, fallback);

    // Assert
    should(actual).equal('/');
  });
});
