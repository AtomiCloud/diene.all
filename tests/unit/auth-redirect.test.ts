import { buildLoginRedirect, resolveReturnTo } from '@atomicloud/diene.auth-engine';
import { describe, it } from 'bun:test';
import should from 'should';

// Login-redirect return: an unauthenticated request to a protected page lands
// back on the page it asked for, INCLUDING its query string, after signing in.
// Two halves — the round trip (build then resolve) and the wiring (the SSR guard
// actually passes a returnTo). Dropping the argument is the sabotage this gate
// catches: without it every login lands on the home page and the deep link is
// silently lost.

const GUARD = 'src/adapters/auth/guard.ts';

describe('login redirect round trip', () => {
  it.each([
    { label: 'a bare path', returnTo: '/settings' },
    { label: 'a path with a query string', returnTo: '/settings?tab=profile' },
    { label: 'a path with multiple params', returnTo: '/reminders?q=milk&sort=due' },
    { label: 'a localized path', returnTo: '/de/settings?tab=profile' },
    { label: 'a path with an encoded space', returnTo: '/search?q=two%20words' },
  ])('should carry $label through the redirect and back', async ({ returnTo }) => {
    // Act — build the login URL the guard would redirect to, then resolve the
    // returnTo back out of it the way the callback route does.
    const redirect = buildLoginRedirect('/api/logto/sign-in', returnTo);
    const raw = new URL(redirect, 'https://app.test').searchParams.get('returnTo') ?? '';
    const resolved = await resolveReturnTo(raw).serial();

    // Assert — path AND query survive intact.
    should(redirect).startWith('/api/logto/sign-in?');
    should(resolved[0]).equal('ok');
    should(resolved[1]).equal(returnTo);
  });

  it.each([
    { label: 'an absolute URL to another origin', raw: 'https://evil.test/steal' },
    { label: 'a protocol-relative URL', raw: '//evil.test/steal' },
    { label: 'a path that is not a path', raw: 'javascript:alert(1)' },
  ])('should reject $label rather than redirect off-origin', async ({ raw }) => {
    // Act
    const resolved = await resolveReturnTo(raw).serial();

    // Assert — an open redirect is a security defect, so the resolver fails
    // closed and the caller falls back to a known-safe path.
    should(resolved[0]).equal('err');
  });
});

describe('SSR guard wiring', () => {
  it('should redirect to login carrying the requested path', async () => {
    // Arrange
    const source = await Bun.file(GUARD).text();

    // Assert — the returnTo argument is present at the call site. A call with the
    // login path alone typechecks fine, so only this assertion catches its loss.
    should(source).match(/redirect\(buildLoginRedirect\('\/api\/logto\/sign-in', returnTo\)\)/);
  });

  it('should take the returnTo from its caller rather than inventing one', async () => {
    // Arrange — a hardcoded returnTo would send every protected page to the same
    // destination, which looks like a working redirect and is not one.
    const source = await Bun.file(GUARD).text();

    // Assert
    should(source).match(/requireSession = async \(returnTo: string\)/);
  });

  it('should check the home claim on every resolved session', async () => {
    // Arrange — the same guard decides picker-vs-home, so a session that signed
    // in without completing onboarding is routed to the picker (ARCHITECTURE §5).
    const source = await Bun.file(GUARD).text();

    // Assert
    should(source).match(/checkHomeLandscape\(claims\)/);
    should(source).match(/phase: 'pre-onboarding'/);
  });
});
