import type { Problem } from '@atomicloud/diene.problems';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { z } from 'zod';
import { type AuthProblems, createInvalidReturnTo } from '../problems';

/**
 * A strict same-origin continuation target: exactly one leading `/`, never `//`
 * or `/\`, no scheme (a `:` may only appear after the first `/`), and no CR/LF.
 * The refinement returns the input byte-for-byte so the safe path and query
 * round-trip exactly.
 */
const returnToSchema = z.string().refine(raw => {
  if (raw === '' || raw[0] !== '/') return false;
  if (raw[1] === '/' || raw[1] === '\\') return false;
  if (raw.includes('\r') || raw.includes('\n')) return false;

  const firstSlash = raw.indexOf('/');
  const firstColon = raw.indexOf(':');
  return firstColon === -1 || firstColon > firstSlash;
});

function isValidReturnTo(raw: string): boolean {
  return returnToSchema.safeParse(raw).success;
}

function fallbackInvalidReturnTo(): Problem {
  return {
    type: 'about:blank',
    title: 'Invalid returnTo',
    status: 400,
    detail: 'The requested continuation URL is invalid.',
    data: {},
  };
}

export function buildLoginRedirect(loginPath: string, returnTo: string): string {
  const fragmentAt = loginPath.indexOf('#');
  const base = fragmentAt === -1 ? loginPath : loginPath.slice(0, fragmentAt);
  const fragment = fragmentAt === -1 ? '' : loginPath.slice(fragmentAt);
  const separator = base.includes('?') ? '&' : '?';
  return `${base}${separator}returnTo=${encodeURIComponent(returnTo.toWellFormed())}${fragment}`;
}

export function resolveReturnTo(
  raw: string,
  problems?: Pick<AuthProblems, 'InvalidReturnTo'>,
): Result<string, Problem> {
  const parsed = returnToSchema.safeParse(raw);
  if (!parsed.success) {
    return Err(problems === undefined ? fallbackInvalidReturnTo() : createInvalidReturnTo(problems));
  }
  return Ok(parsed.data);
}

/** Continue to an already validated target; invalid accidental inputs fail closed to the fallback. */
export function continueTo(validated: string, fallback = '/'): string {
  if (isValidReturnTo(validated)) return validated;
  return isValidReturnTo(fallback) ? fallback : '/';
}
