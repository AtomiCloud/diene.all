import { fromError, fromHttpError, type Problem, type RegisteredProblem } from '@atomicloud/diene.problems';
import { Err, Ok, Res, type Result } from '@atomicloud/diene.result';
import { z } from 'zod';
import type { AuthEngineConfig } from '../../lib/config';
import {
  type DeferredIdentityClient,
  type LogtoUserAccount,
  ONE_TIME_TOKEN_EXPIRES_IN_SECONDS,
  type OneTimeToken,
  REDEEM_INTERACTION_EVENT,
} from '../../lib/deferred/exchange';
import type { AuthProblems } from '../../lib/problems';

/** Minimal Web-standard fetch surface so the adapter stays runtime-agnostic. */
export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;

/** Resolved wire configuration for the Logto Management API M2M client. */
export interface LogtoManagementConfig {
  /** OIDC token endpoint for the M2M `client_credentials` grant. */
  readonly tokenEndpoint: string;
  /** Management API base whose children are `/users/{sub}` and `/one-time-tokens`. */
  readonly apiBaseUrl: string;
  /** Resource indicator requested for the M2M access token. */
  readonly resource: string;
  readonly clientId: string;
  readonly clientSecret: string;
  /** M2M scope; defaults to `all`. */
  readonly scope?: string;
}

/** Dependencies for {@link LogtoManagementClient}. `fetch` is injectable for tests. */
export interface LogtoManagementDeps {
  readonly config: LogtoManagementConfig;
  readonly problems: Pick<AuthProblems, 'AuthRefreshFailed'>;
  readonly fetch?: FetchLike;
}

const httpUrlSchema = z.url().superRefine((value, context) => {
  if (!URL.canParse(value)) return;
  const url = new URL(value);
  if (url.protocol !== 'https:' && url.protocol !== 'http:') {
    context.addIssue({ code: 'custom', message: 'URL must use HTTP or HTTPS.' });
  }
  if (url.username !== '' || url.password !== '' || url.search !== '' || url.hash !== '') {
    context.addIssue({
      code: 'custom',
      message: 'Management URLs must not contain credentials, a query, or a fragment.',
    });
  }
});
const nonBlankSchema = z.string().trim().min(1);
const nonBlankSecretSchema = z.string().refine(value => value.trim() !== '');
const managementConfigSchema = z
  .object({
    tokenEndpoint: httpUrlSchema,
    apiBaseUrl: httpUrlSchema,
    resource: httpUrlSchema,
    clientId: nonBlankSchema,
    clientSecret: nonBlankSecretSchema,
    scope: nonBlankSchema.optional(),
  })
  .strict();

/** Strict schemas for fixed OAuth/OTT wire shapes. */
const tokenResponseSchema = z
  .object({
    access_token: z.string().min(1),
    expires_in: z.number().finite().nonnegative().optional(),
    token_type: z.string().min(1).optional(),
    scope: z.string().optional(),
  })
  .strict();
/** Logto's user resource is extensible; require the two security-critical fields and retain forward compatibility. */
const userResponseSchema = z
  .object({
    isSuspended: z.boolean(),
    primaryEmail: z.string().nullable(),
  })
  .passthrough();
const oneTimeTokenResponseSchema = z
  .object({
    token: z.string().min(1),
    id: z.string().optional(),
    email: z.string().optional(),
  })
  .strict();

function isBlank(value: string): boolean {
  return value.trim() === '';
}

/**
 * Derive the Management API wire config from the engine config block. The Logto
 * Management API lives at `{endpoint}/api`; the M2M resource indicator is that
 * same base. A trailing `/api` on the configured management endpoint is
 * tolerated so the base is never doubled.
 */
export function managementConfigFromAuthEngine(config: AuthEngineConfig): LogtoManagementConfig {
  const oidc = config.logto.endpoint.replace(/\/+$/, '');
  const managementBase = config.logto.management.endpoint.replace(/\/+$/, '').replace(/\/api$/, '');
  const apiBaseUrl = `${managementBase}/api`;
  return {
    tokenEndpoint: `${oidc}/oidc/token`,
    apiBaseUrl,
    resource: apiBaseUrl,
    clientId: config.logto.management.clientId,
    clientSecret: config.logto.management.clientSecret,
    scope: 'all',
  };
}

function problemFromError(error: unknown, fallback: RegisteredProblem): Problem {
  return fromError(error, { fallback, fallbackData: () => ({}) });
}

function problemFromHttp(response: Response, fallback: RegisteredProblem): Promise<Problem> {
  return fromHttpError(response, { fallback, fallbackData: () => ({}) });
}

async function readJson(response: Response): Promise<unknown> {
  try {
    return await response.json();
  } catch {
    return {};
  }
}

/**
 * Acquire an M2M access token via the OIDC `client_credentials` grant. Stateless
 * by design — no cached token is held on the adapter (single-flight caching is
 * the engine's separate concern), so the client carries no mutable state.
 */
async function acquireAccessToken(
  config: LogtoManagementConfig,
  fetchLike: FetchLike,
  fallback: RegisteredProblem,
): Promise<Result<string, Problem>> {
  let response: Response;
  try {
    const basic = btoa(`${config.clientId}:${config.clientSecret}`);
    const form = new URLSearchParams({
      grant_type: 'client_credentials',
      resource: config.resource,
      scope: config.scope ?? 'all',
    });
    response = await fetchLike(config.tokenEndpoint, {
      method: 'POST',
      headers: {
        authorization: `Basic ${basic}`,
        'content-type': 'application/x-www-form-urlencoded',
        accept: 'application/json',
      },
      body: form.toString(),
    });
  } catch (error) {
    return Err(problemFromError(error, fallback));
  }
  if (!response.ok) {
    return Err(await problemFromHttp(response, fallback));
  }
  const parsed = tokenResponseSchema.safeParse(await readJson(response));
  if (!parsed.success) {
    return Err(problemFromError(new Error('Logto token response was missing an access_token.'), fallback));
  }
  return Ok(parsed.data.access_token);
}

/**
 * Logto Management API adapter (int ledger). Talks the OIDC/Management HTTP APIs
 * directly with `fetch` — no `@logto/*` SDK — to keep the wire contract explicit
 * and the surface edge-safe. Stateless: only immutable dependency fields.
 */
export class LogtoManagementClient implements DeferredIdentityClient {
  readonly #config: LogtoManagementConfig;
  readonly #fallback: RegisteredProblem;
  readonly #fetch: FetchLike;

  constructor(deps: LogtoManagementDeps) {
    this.#config = deps.config;
    this.#fallback = deps.problems.AuthRefreshFailed;
    this.#fetch = deps.fetch ?? ((input, init) => fetch(input, init));
  }

  getUser(sub: string): Result<LogtoUserAccount, Problem> {
    return Res.async<LogtoUserAccount, Problem>(async () => {
      // M33: reject a blank sub before acquiring any M2M token or hitting the network.
      if (isBlank(sub)) {
        return Err(problemFromError(new Error('A non-blank sub is required to resolve a user.'), this.#fallback));
      }

      const parsedConfig = managementConfigSchema.safeParse(this.#config);
      if (!parsedConfig.success) {
        return Err(problemFromError(new Error('The Logto Management configuration is invalid.'), this.#fallback));
      }

      const token = await acquireAccessToken(parsedConfig.data, this.#fetch, this.#fallback);
      if (!(await token.isOk())) {
        return Err(await token.unwrapErr());
      }
      const bearer = await token.unwrap();

      let response: Response;
      try {
        response = await this.#fetch(`${parsedConfig.data.apiBaseUrl}/users/${encodeURIComponent(sub)}`, {
          method: 'GET',
          headers: { authorization: `Bearer ${bearer}`, accept: 'application/json' },
        });
      } catch (error) {
        return Err(problemFromError(error, this.#fallback));
      }
      if (!response.ok) {
        return Err(await problemFromHttp(response, this.#fallback));
      }
      const parsed = userResponseSchema.safeParse(await readJson(response));
      if (!parsed.success) {
        return Err(problemFromError(new Error('Logto user response was malformed.'), this.#fallback));
      }
      return Ok({
        isSuspended: parsed.data.isSuspended,
        primaryEmail: parsed.data.primaryEmail,
      });
    });
  }

  mintOneTimeToken(email: string): Result<OneTimeToken, Problem> {
    return Res.async<OneTimeToken, Problem>(async () => {
      // M33: reject a blank email before acquiring any M2M token or hitting the network.
      if (isBlank(email)) {
        return Err(
          problemFromError(new Error('A non-blank email is required to mint a one-time token.'), this.#fallback),
        );
      }

      const parsedConfig = managementConfigSchema.safeParse(this.#config);
      if (!parsedConfig.success) {
        return Err(problemFromError(new Error('The Logto Management configuration is invalid.'), this.#fallback));
      }

      const token = await acquireAccessToken(parsedConfig.data, this.#fetch, this.#fallback);
      if (!(await token.isOk())) {
        return Err(await token.unwrapErr());
      }
      const bearer = await token.unwrap();

      let response: Response;
      try {
        response = await this.#fetch(`${parsedConfig.data.apiBaseUrl}/one-time-tokens`, {
          method: 'POST',
          headers: {
            authorization: `Bearer ${bearer}`,
            'content-type': 'application/json',
            accept: 'application/json',
          },
          body: JSON.stringify({
            email,
            expiresIn: ONE_TIME_TOKEN_EXPIRES_IN_SECONDS,
            context: { interactionEvent: REDEEM_INTERACTION_EVENT },
          }),
        });
      } catch (error) {
        return Err(problemFromError(error, this.#fallback));
      }
      if (!response.ok) {
        return Err(await problemFromHttp(response, this.#fallback));
      }
      const parsed = oneTimeTokenResponseSchema.safeParse(await readJson(response));
      if (!parsed.success) {
        return Err(problemFromError(new Error('Logto one-time-token response was missing a token.'), this.#fallback));
      }
      return Ok({ token: parsed.data.token });
    });
  }
}
