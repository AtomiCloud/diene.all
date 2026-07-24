import { fromHttpError, type Problem } from '@atomicloud/diene.problems';
import { Err, Ok, Res, type Result } from '@atomicloud/diene.result';
import { Temporal } from '@js-temporal/polyfill';
import { z } from 'zod';
import { type AuthProblems, createAppHandoffExpired, createAuthRefreshFailed, createUnauthorized } from '../problems';

/** Default handoff mount path (C0 §7); the mint route is `POST {mount}`. */
export const DEFAULT_HANDOFF_MOUNT = '/app-handoff';

/** Minimal Web-standard fetch surface — keeps the web client edge/runtime-agnostic. */
export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;

/** Dependencies for {@link initiateHandoff} (web client). */
export interface InitiateHandoffDeps {
  readonly fetch: FetchLike;
  /** Origin the handoff host is mounted on, e.g. `https://api.example.com`. */
  readonly baseUrl: string;
  /** Configured mount path; defaults to `/app-handoff`. Never gets a second segment appended. */
  readonly mount?: string;
  /** Bearer access token from the authenticated retriever/session. */
  readonly accessToken: string;
  readonly problems: Pick<AuthProblems, 'AppHandoffExpired' | 'AuthRefreshFailed' | 'Unauthorized'>;
}

/** The mint response returned to the web client; `expiresAt` is a domain instant. */
export interface InitiateHandoffResult {
  readonly nonce: string;
  readonly expiresAt: Temporal.Instant;
}

/** A minted nonce is 32 random bytes → 43 unpadded base64url characters. */
const NONCE_PATTERN = /^[A-Za-z0-9_-]{43}$/;

/** The mint response is validated at the wire boundary: exact nonce shape, non-empty expiry. */
const mintResponseSchema = z
  .object({
    nonce: z.string().regex(NONCE_PATTERN),
    expiresAt: z.string().min(1),
  })
  .strict();

const handoffBaseUrlSchema = z.url().superRefine((value, context) => {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return;
  }
  if (url.protocol !== 'https:' && url.protocol !== 'http:') {
    context.addIssue({ code: 'custom', message: 'The handoff base URL must use HTTP or HTTPS.' });
  }
  if (url.username !== '' || url.password !== '' || url.search !== '' || url.hash !== '' || url.pathname !== '/') {
    context.addIssue({
      code: 'custom',
      message: 'The handoff base URL must be an origin without credentials, path, query, or fragment.',
    });
  }
});

const handoffMountSchema = z
  .string()
  .regex(/^\/(?!\/)(?!.*\/\/)(?!.*[\\%?#\s]).*$/)
  .refine(value => !/(^|\/)\.{1,2}(\/|$)/.test(value));

const handoffRequestSchema = z
  .object({
    baseUrl: handoffBaseUrlSchema,
    mount: handoffMountSchema,
    accessToken: z.string().refine(value => value.trim() !== ''),
  })
  .strict();

function isBlank(value: string): boolean {
  return value.trim() === '';
}

function joinUrl(baseUrl: string, mount: string): string {
  const base = baseUrl.replace(/\/+$/, '');
  const path = mount.startsWith('/') ? mount : `/${mount}`;
  return `${base}${path}`;
}

/**
 * Initiate a deferred handoff from the web client (C0 §7): authenticated
 * `POST {mount}` with an empty body.
 *
 * Preconditions checked BEFORE any fetch: a blank bearer rejects with a generic
 * `Unauthorized`; a blank base URL or mount rejects with `AuthRefreshFailed`. On
 * `200` the response is validated (nonce must be an exact 43-char base64url
 * string) and the RFC 3339 expiry is deserialised into a `Temporal.Instant`; a
 * `410` collapses to the generic `AppHandoffExpired`, and any other
 * transport/HTTP failure maps through the problem transformer with an
 * `AuthRefreshFailed` fallback.
 */
export function initiateHandoff(deps: InitiateHandoffDeps): Result<InitiateHandoffResult, Problem> {
  const fallbackData = () => ({});

  return Res.async<InitiateHandoffResult, Problem>(async () => {
    // Preconditions — no fetch is attempted until these pass.
    if (isBlank(deps.accessToken)) {
      return Err(createUnauthorized(deps.problems, 'A bearer access token is required to initiate a handoff.'));
    }
    const mount = deps.mount ?? DEFAULT_HANDOFF_MOUNT;
    const parsedRequest = handoffRequestSchema.safeParse({
      baseUrl: deps.baseUrl,
      mount,
      accessToken: deps.accessToken,
    });
    if (!parsedRequest.success) {
      return Err(createAuthRefreshFailed(deps.problems, 'The handoff base URL or mount is invalid.'));
    }
    const url = joinUrl(parsedRequest.data.baseUrl, parsedRequest.data.mount);

    let response: Response;
    try {
      response = await deps.fetch(url, {
        method: 'POST',
        headers: {
          authorization: `Bearer ${parsedRequest.data.accessToken}`,
          'content-type': 'application/json',
        },
        body: '{}',
      });
    } catch (error) {
      return Err(createAuthRefreshFailed(deps.problems, errorMessage(error)));
    }

    if (response.status === 410) {
      return Err(createAppHandoffExpired(deps.problems));
    }
    if (!response.ok) {
      return Err(
        await fromHttpError(response, {
          fallback: deps.problems.AuthRefreshFailed,
          fallbackData,
        }),
      );
    }

    const parsed = mintResponseSchema.safeParse(await safeJson(response));
    if (!parsed.success) {
      return Err(createAuthRefreshFailed(deps.problems, 'The handoff mint response was malformed.'));
    }
    // Deserialise the wire RFC 3339 instant into the domain type at this boundary.
    let expiresAt: Temporal.Instant;
    try {
      expiresAt = Temporal.Instant.from(parsed.data.expiresAt);
    } catch {
      return Err(createAuthRefreshFailed(deps.problems, 'The handoff mint response carried an invalid expiry.'));
    }
    return Ok({ nonce: parsed.data.nonce, expiresAt });
  });
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : 'The handoff request could not be completed.';
}

async function safeJson(response: Response): Promise<unknown> {
  try {
    return await response.json();
  } catch {
    return undefined;
  }
}
