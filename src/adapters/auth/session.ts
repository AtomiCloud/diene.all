import 'server-only';

import { Ok, type Result } from '@atomicloud/diene.result';
import type { LogtoTokenSession, LogtoTokenStorage } from '@atomicloud/diene.auth-engine';
import type { Problem } from '@atomicloud/diene.problems';
import { cookies } from 'next/headers';

const SESSION_COOKIE = 'diene.auth.session';

/**
 * Cookie-backed LogtoTokenStorage: the auth-engine provider holds no session
 * state itself; this adapter persists the token session in an httpOnly cookie
 * scoped to the server. Works identically on the Worker isolate and the Garden
 * standalone server; secrets never enter the browser-readable surface.
 */
export const cookieTokenStorage = (jar: Awaited<ReturnType<typeof cookies>>, secure: boolean): LogtoTokenStorage => ({
  get: (): Result<LogtoTokenSession | undefined, Problem> => {
    const raw = jar.get(SESSION_COOKIE)?.value;
    if (raw === undefined || raw === '') return Ok(undefined);
    try {
      return Ok(JSON.parse(raw) as LogtoTokenSession);
    } catch {
      return Ok(undefined);
    }
  },
  set: (session: LogtoTokenSession): Result<void, Problem> => {
    jar.set(SESSION_COOKIE, JSON.stringify(session), {
      httpOnly: true,
      sameSite: 'lax',
      secure,
      path: '/',
      // Refresh lifetime bounds the cookie: 14 days rotating (ARCHITECTURE §5).
      maxAge: 14 * 24 * 60 * 60,
    });
    return Ok(undefined);
  },
  clear: (): Result<void, Problem> => {
    jar.delete(SESSION_COOKIE);
    return Ok(undefined);
  },
});

/** Whether a server session cookie exists (cheap signed-in hint for guards). */
export const hasSessionCookie = (jar: Awaited<ReturnType<typeof cookies>>): boolean =>
  (jar.get(SESSION_COOKIE)?.value ?? '') !== '';
