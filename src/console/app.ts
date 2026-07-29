import type { Context } from 'hono';
import { Hono } from 'hono';
import { getCookie, setCookie } from 'hono/cookie';
import type { ContentfulStatusCode } from 'hono/utils/http-status';
import type {
  ConsoleCapability,
  ConsoleEventStatus,
  ConsoleFailure,
  ConsoleFilters,
  ConsoleNativeAuthorization,
  ConsoleResult,
  ConsoleSessionTicket,
} from './model.ts';
import type {
  ConsoleAuthorizationExchange,
  ConsoleClock,
  ConsoleIncidentReporter,
  ConsoleManagementAccountGateway,
  ConsoleOperations,
  ConsoleRequestSecurity,
  ConsoleSessions,
} from './ports.ts';
import {
  type ConfirmationKind,
  renderConfirmation,
  renderDashboard,
  renderEvent,
  renderFailure,
  renderLogin,
  renderOutcome,
  renderPublicFailure,
} from './views.ts';

const SESSION_COOKIE = '__Host-mercury_console_session';
const LOGIN_CSRF_COOKIE = '__Host-mercury_console_login_csrf';
const MAX_FORM_BYTES = 8_192;
const LOGIN_CSRF_TTL_SECONDS = 600;
const EVENT_STATUSES: readonly ConsoleEventStatus[] = [
  'all',
  'queued',
  'delivering',
  'retrying',
  'delivered',
  'dead-lettered',
  'withheld',
];
const FILTER_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$/;
const IDENTIFIER_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
const ACCOUNT_NAME_PATTERN = /^(?:internal|external)\/[^\s\0]{1,239}$/u;

export interface ConsoleAppDependencies {
  readonly clock: ConsoleClock;
  readonly sessions: ConsoleSessions;
  readonly managementGateway: ConsoleManagementAccountGateway;
  readonly authorization: ConsoleAuthorizationExchange;
  readonly operations: ConsoleOperations;
  readonly requestSecurity: ConsoleRequestSecurity;
  readonly incidentReporter: ConsoleIncidentReporter;
}

export interface ConsoleAppOptions {
  readonly origin: string;
}

interface ActiveConsoleRequest {
  readonly ticket: ConsoleSessionTicket;
  readonly authorization: ConsoleNativeAuthorization;
}

type ActiveConsoleRequestResult =
  | { readonly ok: true; readonly value: ActiveConsoleRequest }
  | {
      readonly ok: false;
      readonly error: ConsoleFailure;
      readonly ticket?: ConsoleSessionTicket;
    };

const failure = (
  kind: ConsoleFailure['kind'],
  title: string,
  detail: string,
  retryAfterSeconds?: number,
): ConsoleFailure => ({ kind, title, detail, retryAfterSeconds });

const failureStatus = (value: ConsoleFailure): ContentfulStatusCode => {
  switch (value.kind) {
    case 'bad-request':
      return 400;
    case 'payload-too-large':
      return 413;
    case 'unauthenticated':
      return 401;
    case 'forbidden':
      return 403;
    case 'not-found':
      return 404;
    case 'conflict':
      return 409;
    case 'rate-limited':
      return 429;
    case 'unavailable':
      return 503;
    case 'unexpected':
      return 500;
  }
};

const applySecurityHeaders = (context: Context, nonce: string): void => {
  context.header('Cache-Control', 'no-store, private, max-age=0');
  context.header('Pragma', 'no-cache');
  context.header(
    'Content-Security-Policy',
    [
      "default-src 'none'",
      `script-src 'nonce-${nonce}'`,
      `style-src 'nonce-${nonce}'`,
      "img-src 'self' data:",
      "font-src 'self'",
      "connect-src 'self'",
      "form-action 'self'",
      "frame-ancestors 'none'",
      "base-uri 'none'",
      "object-src 'none'",
      'upgrade-insecure-requests',
    ].join('; '),
  );
  context.header('Cross-Origin-Opener-Policy', 'same-origin');
  context.header('Cross-Origin-Resource-Policy', 'same-origin');
  context.header('Permissions-Policy', 'camera=(), geolocation=(), microphone=(), payment=()');
  context.header('Referrer-Policy', 'no-referrer');
  context.header('Strict-Transport-Security', 'max-age=63072000; includeSubDomains');
  context.header('Vary', 'Cookie');
  context.header('X-Content-Type-Options', 'nosniff');
  context.header('X-Frame-Options', 'DENY');
};

const html = (context: Context, nonce: string, document: string, status: ContentfulStatusCode = 200): Response => {
  applySecurityHeaders(context, nonce);
  return context.html(document, status);
};

const redirect = (context: Context, location: string): Response => {
  context.header('Cache-Control', 'no-store, private, max-age=0');
  context.header('Referrer-Policy', 'no-referrer');
  context.header('X-Content-Type-Options', 'nosniff');
  return context.redirect(location, 303);
};

const setSessionCookie = (context: Context, ticket: ConsoleSessionTicket): void => {
  setCookie(context, SESSION_COOKIE, ticket.token, {
    expires: ticket.expiresAt,
    httpOnly: true,
    path: '/',
    priority: 'High',
    sameSite: 'Strict',
    secure: true,
  });
};

const clearCookie = (context: Context, name: string): void => {
  setCookie(context, name, '', {
    expires: new Date(0),
    httpOnly: true,
    maxAge: 0,
    path: '/',
    priority: 'High',
    sameSite: 'Strict',
    secure: true,
  });
};

const setLoginCsrfCookie = (context: Context, token: string, now: Date): void => {
  setCookie(context, LOGIN_CSRF_COOKIE, token, {
    expires: new Date(now.getTime() + LOGIN_CSRF_TTL_SECONDS * 1_000),
    httpOnly: true,
    maxAge: LOGIN_CSRF_TTL_SECONDS,
    path: '/',
    priority: 'High',
    sameSite: 'Strict',
    secure: true,
  });
};

const readUrlEncodedForm = async (request: Request): Promise<ConsoleResult<URLSearchParams>> => {
  const contentType = request.headers.get('content-type')?.split(';', 1)[0]?.trim().toLowerCase();
  if (contentType !== 'application/x-www-form-urlencoded') {
    return {
      ok: false,
      error: failure(
        'bad-request',
        'Unsupported form encoding',
        'Console forms require application/x-www-form-urlencoded.',
      ),
    };
  }

  const tooLarge = (): ConsoleResult<URLSearchParams> => ({
    ok: false,
    error: failure('payload-too-large', 'Form is too large', 'The submitted form exceeds 8 KiB.'),
  });
  const cancelBody = async (): Promise<void> => {
    try {
      await request.body?.cancel();
    } catch {
      // The response is still a fail-closed 413 if the peer has already errored the stream.
    }
  };
  const declaredLengthHeader = request.headers.get('content-length');
  const declaredLength = declaredLengthHeader === null ? undefined : Number(declaredLengthHeader);
  if (declaredLength !== undefined && Number.isFinite(declaredLength) && declaredLength > MAX_FORM_BYTES) {
    await cancelBody();
    return tooLarge();
  }

  const stream = request.body;
  if (stream === null) return { ok: true, value: new URLSearchParams() };
  const reader = stream.getReader();
  const bytes = new Uint8Array(MAX_FORM_BYTES);
  let byteLength = 0;
  try {
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      if (chunk.value.byteLength > MAX_FORM_BYTES - byteLength) {
        try {
          await reader.cancel();
        } catch {
          // The size violation is authoritative even if cancellation races a peer error.
        }
        return tooLarge();
      }
      bytes.set(chunk.value, byteLength);
      byteLength += chunk.value.byteLength;
    }
  } catch {
    return {
      ok: false,
      error: failure('bad-request', 'Form could not be read', 'The submitted form body could not be read.'),
    };
  } finally {
    reader.releaseLock();
  }

  const body = new TextDecoder().decode(bytes.subarray(0, byteLength));
  return { ok: true, value: new URLSearchParams(body) };
};

const singleField = (
  form: URLSearchParams,
  name: string,
  minimumLength: number,
  maximumLength: number,
  trim = true,
): ConsoleResult<string> => {
  const values = form.getAll(name);
  const rawValue = values[0];
  const value = trim ? rawValue?.trim() : rawValue;
  if (values.length !== 1 || value === undefined || value.length < minimumLength || value.length > maximumLength) {
    return {
      ok: false,
      error: failure('bad-request', 'Invalid form', `The ${name} field is invalid.`),
    };
  }
  return { ok: true, value };
};

const isTrustedMutation = (request: Request, expectedOrigin: string): boolean => {
  if (request.headers.get('origin') !== expectedOrigin) return false;
  const fetchSite = request.headers.get('sec-fetch-site');
  return fetchSite === null || fetchSite === 'same-origin';
};

const parseFilter = (
  query: Record<string, string>,
  key: 'landscape' | 'tenant' | 'provider' | 'endpoint',
): ConsoleResult<string | undefined> => {
  const value = query[key]?.trim();
  if (value === undefined || value === '') return { ok: true, value: undefined };
  if (!FILTER_PATTERN.test(value)) {
    return {
      ok: false,
      error: failure('bad-request', 'Invalid filter', `The ${key} filter is invalid.`),
    };
  }
  return { ok: true, value };
};

const parseFilters = (query: Record<string, string>): ConsoleResult<ConsoleFilters> => {
  const landscape = parseFilter(query, 'landscape');
  const tenant = parseFilter(query, 'tenant');
  const provider = parseFilter(query, 'provider');
  const endpoint = parseFilter(query, 'endpoint');
  const status = query.status?.trim() ?? 'all';
  if (!landscape.ok) return landscape;
  if (!tenant.ok) return tenant;
  if (!provider.ok) return provider;
  if (!endpoint.ok) return endpoint;
  if (!EVENT_STATUSES.includes(status as ConsoleEventStatus)) {
    return {
      ok: false,
      error: failure('bad-request', 'Invalid filter', 'The status filter is invalid.'),
    };
  }

  return {
    ok: true,
    value: {
      landscape: landscape.value,
      tenant: tenant.value,
      provider: provider.value,
      endpoint: endpoint.value,
      status: status as ConsoleEventStatus,
    },
  };
};

const inScope = (scope: '*' | readonly string[], selected: string | undefined): boolean =>
  selected === undefined || scope === '*' || scope.includes(selected);

const filtersAreAuthorized = (authorization: ConsoleNativeAuthorization, filters: ConsoleFilters): boolean =>
  inScope(authorization.scope.landscapes, filters.landscape) && inScope(authorization.scope.tenants, filters.tenant);

const validIdentifier = (value: string | undefined): value is string =>
  value !== undefined && IDENTIFIER_PATTERN.test(value);

const authorizationIsUsable = (
  authorization: ConsoleNativeAuthorization,
  ticket: ConsoleSessionTicket,
  requested: readonly ConsoleCapability[],
  now: Date,
): boolean =>
  authorization.scheme === 'Bearer' &&
  authorization.token.length >= 16 &&
  authorization.accountId === ticket.identity.accountId &&
  authorization.sessionId === ticket.sessionId &&
  authorization.expiresAt.getTime() > now.getTime() &&
  (ticket.scope.tenants === '*' ||
    (authorization.scope.tenants !== '*' &&
      authorization.scope.tenants.every(tenant => ticket.scope.tenants.includes(tenant)))) &&
  (ticket.scope.landscapes === '*' ||
    (authorization.scope.landscapes !== '*' &&
      authorization.scope.landscapes.every(landscape => ticket.scope.landscapes.includes(landscape)))) &&
  authorization.scope.capabilities.every(capability => ticket.scope.capabilities.includes(capability)) &&
  requested.every(capability => authorization.scope.capabilities.includes(capability));

export const createConsoleApp = (dependencies: ConsoleAppDependencies, options: ConsoleAppOptions): Hono => {
  const configuredOrigin = new URL(options.origin);
  if (configuredOrigin.origin !== options.origin || configuredOrigin.protocol !== 'https:') {
    throw new Error('Console origin must be an HTTPS origin without a path');
  }

  const app = new Hono();
  const nonce = (): string => dependencies.requestSecurity.issueToken(18);

  const resolveTicket = async (context: Context): Promise<ConsoleSessionTicket | undefined> => {
    const token = getCookie(context, SESSION_COOKIE);
    if (token === undefined) return undefined;

    const resolution = await dependencies.sessions.resolve(token, dependencies.clock.now());
    if (resolution.kind !== 'active') {
      clearCookie(context, SESSION_COOKIE);
      return undefined;
    }
    setSessionCookie(context, resolution.ticket);
    return resolution.ticket;
  };

  const authorize = async (
    ticket: ConsoleSessionTicket,
    requiredCapabilities: readonly ConsoleCapability[],
    optionalCapabilities: readonly ConsoleCapability[] = [],
  ): Promise<ConsoleResult<ConsoleNativeAuthorization>> => {
    const exchanged = await dependencies.authorization.exchange({
      sessionId: ticket.sessionId,
      identity: ticket.identity,
      scope: ticket.scope,
      requiredCapabilities,
      optionalCapabilities,
    });
    if (!exchanged.ok) return exchanged;
    if (!authorizationIsUsable(exchanged.value, ticket, requiredCapabilities, dependencies.clock.now())) {
      return {
        ok: false,
        error: failure(
          'forbidden',
          'Authorization boundary rejected',
          'The scoped native authorization did not satisfy this console operation.',
        ),
      };
    }
    return exchanged;
  };

  const activeRequest = async (
    context: Context,
    requiredCapabilities: readonly ConsoleCapability[],
    optionalCapabilities: readonly ConsoleCapability[] = [],
  ): Promise<ActiveConsoleRequestResult> => {
    const ticket = await resolveTicket(context);
    if (ticket === undefined) {
      return {
        ok: false,
        error: failure('unauthenticated', 'Session required', 'Sign in to continue.'),
      };
    }
    const exchanged = await authorize(ticket, requiredCapabilities, optionalCapabilities);
    return exchanged.ok
      ? { ok: true, value: { ticket, authorization: exchanged.value } }
      : { ok: false, error: exchanged.error, ticket };
  };

  const renderActiveFailure = (
    context: Context,
    requestNonce: string,
    ticket: ConsoleSessionTicket,
    error: ConsoleFailure,
  ): Response => {
    if (error.retryAfterSeconds !== undefined) {
      context.header('Retry-After', String(error.retryAfterSeconds));
    }
    return html(
      context,
      requestNonce,
      renderFailure({
        nonce: requestNonce,
        identity: ticket.identity,
        csrfToken: ticket.csrfToken,
        failure: error,
      }),
      failureStatus(error),
    );
  };

  const renderInactive = (
    context: Context,
    requestNonce: string,
    inactive: Exclude<ActiveConsoleRequestResult, { readonly ok: true }>,
  ): Response =>
    inactive.ticket === undefined
      ? redirect(context, '/console/login')
      : renderActiveFailure(context, requestNonce, inactive.ticket, inactive.error);

  const requireMutation = async (
    context: Context,
    ticket: ConsoleSessionTicket,
  ): Promise<ConsoleResult<URLSearchParams>> => {
    if (!isTrustedMutation(context.req.raw, configuredOrigin.origin)) {
      return {
        ok: false,
        error: failure(
          'forbidden',
          'Cross-site request rejected',
          'The request origin did not match the configured console origin.',
        ),
      };
    }
    const parsed = await readUrlEncodedForm(context.req.raw);
    if (!parsed.ok) return parsed;
    const csrf = singleField(parsed.value, 'csrf', 20, 256);
    if (!csrf.ok || !dependencies.requestSecurity.equal(csrf.value, ticket.requestCsrfToken)) {
      return {
        ok: false,
        error: failure(
          'forbidden',
          'CSRF validation failed',
          'Refresh the console page and submit the operation again.',
        ),
      };
    }
    return parsed;
  };

  app.get('/console/login', async context => {
    const requestNonce = nonce();
    const existing = await resolveTicket(context);
    if (existing !== undefined) return redirect(context, '/console');

    const csrfToken = dependencies.requestSecurity.issueToken(32);
    setLoginCsrfCookie(context, csrfToken, dependencies.clock.now());
    return html(context, requestNonce, renderLogin({ nonce: requestNonce, csrfToken }));
  });

  app.post('/console/login', async context => {
    const requestNonce = nonce();
    if (!isTrustedMutation(context.req.raw, configuredOrigin.origin)) {
      const csrfToken = dependencies.requestSecurity.issueToken(32);
      setLoginCsrfCookie(context, csrfToken, dependencies.clock.now());
      return html(
        context,
        requestNonce,
        renderLogin({
          nonce: requestNonce,
          csrfToken,
          failure: failure('forbidden', 'Sign-in request rejected', 'Refresh the sign-in page and try again.'),
        }),
        403,
      );
    }

    const parsed = await readUrlEncodedForm(context.req.raw);
    const loginCookie = getCookie(context, LOGIN_CSRF_COOKIE);
    const submittedCsrf = parsed.ok ? singleField(parsed.value, 'csrf', 20, 256) : parsed;
    if (
      !parsed.ok ||
      loginCookie === undefined ||
      !submittedCsrf.ok ||
      !dependencies.requestSecurity.equal(loginCookie, submittedCsrf.value)
    ) {
      const csrfToken = dependencies.requestSecurity.issueToken(32);
      setLoginCsrfCookie(context, csrfToken, dependencies.clock.now());
      return html(
        context,
        requestNonce,
        renderLogin({
          nonce: requestNonce,
          csrfToken,
          failure: failure('forbidden', 'Sign-in request rejected', 'Refresh the sign-in page and try again.'),
        }),
        parsed.ok ? 403 : failureStatus(parsed.error),
      );
    }

    const accountName = singleField(parsed.value, 'accountName', 1, 256);
    const bearerCredential = singleField(parsed.value, 'bearerCredential', 16, 512, false);
    const accountNameValid = accountName.ok && ACCOUNT_NAME_PATTERN.test(accountName.value);
    const bearerCredentialValid = bearerCredential.ok && !/\s|\0/.test(bearerCredential.value);
    if (!accountNameValid || !bearerCredentialValid) {
      const csrfToken = dependencies.requestSecurity.issueToken(32);
      setLoginCsrfCookie(context, csrfToken, dependencies.clock.now());
      return html(
        context,
        requestNonce,
        renderLogin({
          nonce: requestNonce,
          csrfToken,
          accountName: accountName.ok ? accountName.value : undefined,
          failure: failure('unauthenticated', 'Unable to authenticate', 'The account credentials were not accepted.'),
        }),
        401,
      );
    }

    const authentication = await dependencies.managementGateway.authenticate({
      accountName: accountName.value,
      bearerCredential: bearerCredential.value,
    });
    if (authentication.kind !== 'authenticated') {
      const csrfToken = dependencies.requestSecurity.issueToken(32);
      setLoginCsrfCookie(context, csrfToken, dependencies.clock.now());
      const retryAfter = authentication.kind === 'rate-limited' ? authentication.retryAfterSeconds : undefined;
      if (retryAfter !== undefined) context.header('Retry-After', String(retryAfter));
      return html(
        context,
        requestNonce,
        renderLogin({
          nonce: requestNonce,
          csrfToken,
          accountName: accountName.value,
          failure: failure(
            authentication.kind === 'rate-limited' ? 'rate-limited' : 'unauthenticated',
            'Unable to authenticate',
            authentication.kind === 'rate-limited'
              ? 'Too many attempts. Wait before trying again.'
              : 'The account credentials were not accepted.',
            retryAfter,
          ),
        }),
        authentication.kind === 'rate-limited' ? 429 : 401,
      );
    }

    const previousSessionToken = getCookie(context, SESSION_COOKIE);
    if (previousSessionToken !== undefined) {
      await dependencies.sessions.revoke(previousSessionToken);
    }
    const ticket = await dependencies.sessions.create(
      authentication.identity,
      authentication.scope,
      dependencies.clock.now(),
    );
    setSessionCookie(context, ticket);
    clearCookie(context, LOGIN_CSRF_COOKIE);
    return redirect(context, '/console');
  });

  app.post('/console/logout', async context => {
    const requestNonce = nonce();
    const ticket = await resolveTicket(context);
    if (ticket === undefined) return redirect(context, '/console/login');
    const mutation = await requireMutation(context, ticket);
    if (!mutation.ok) return renderActiveFailure(context, requestNonce, ticket, mutation.error);

    await dependencies.sessions.revoke(ticket.token);
    clearCookie(context, SESSION_COOKIE);
    clearCookie(context, LOGIN_CSRF_COOKIE);
    return redirect(context, '/console/login');
  });

  app.get('/console', async context => {
    const requestNonce = nonce();
    const active = await activeRequest(
      context,
      ['operations:read'],
      ['events:replay', 'endpoints:replay', 'endpoints:reenable'],
    );
    if (!active.ok) {
      return renderInactive(context, requestNonce, active);
    }
    const filters = parseFilters(context.req.query());
    if (!filters.ok) {
      return renderActiveFailure(context, requestNonce, active.value.ticket, filters.error);
    }
    if (!filtersAreAuthorized(active.value.authorization, filters.value)) {
      return renderActiveFailure(
        context,
        requestNonce,
        active.value.ticket,
        failure(
          'forbidden',
          'Filter is outside account scope',
          'The selected tenant or landscape is not authorized for this account.',
        ),
      );
    }
    const snapshot = await dependencies.operations.dashboard(active.value.authorization, filters.value);
    if (!snapshot.ok) {
      return renderActiveFailure(context, requestNonce, active.value.ticket, snapshot.error);
    }
    return html(
      context,
      requestNonce,
      renderDashboard({
        nonce: requestNonce,
        identity: active.value.ticket.identity,
        csrfToken: active.value.ticket.csrfToken,
        snapshot: snapshot.value,
        filters: filters.value,
        capabilities: active.value.authorization.scope.capabilities,
      }),
    );
  });

  app.get('/console/events/:landscape/:eventId', async context => {
    const requestNonce = nonce();
    const active = await activeRequest(context, ['operations:read'], ['events:replay']);
    if (!active.ok) return renderInactive(context, requestNonce, active);
    const landscape = context.req.param('landscape');
    const eventId = context.req.param('eventId');
    if (
      !validIdentifier(landscape) ||
      !validIdentifier(eventId) ||
      !inScope(active.value.authorization.scope.landscapes, landscape)
    ) {
      return renderActiveFailure(
        context,
        requestNonce,
        active.value.ticket,
        failure('bad-request', 'Invalid event reference', 'The event reference is invalid.'),
      );
    }
    const event = await dependencies.operations.event(active.value.authorization, landscape, eventId);
    if (!event.ok) {
      return renderActiveFailure(context, requestNonce, active.value.ticket, event.error);
    }
    return html(
      context,
      requestNonce,
      renderEvent({
        nonce: requestNonce,
        identity: active.value.ticket.identity,
        csrfToken: active.value.ticket.csrfToken,
        event: event.value,
        canReplay: active.value.authorization.scope.capabilities.includes('events:replay'),
      }),
    );
  });

  const confirmation = async (
    context: Context,
    kind: ConfirmationKind,
    capability: ConsoleCapability,
  ): Promise<Response> => {
    const requestNonce = nonce();
    const active = await activeRequest(context, ['operations:read', capability]);
    if (!active.ok) {
      return renderInactive(context, requestNonce, active);
    }
    if (kind === 'replay-event') {
      const landscape = context.req.param('landscape');
      const eventId = context.req.param('eventId');
      const selectedEndpointId = context.req.query('endpoint');
      if (
        !validIdentifier(landscape) ||
        !validIdentifier(eventId) ||
        (selectedEndpointId !== undefined && !validIdentifier(selectedEndpointId)) ||
        !inScope(active.value.authorization.scope.landscapes, landscape)
      ) {
        return renderActiveFailure(
          context,
          requestNonce,
          active.value.ticket,
          failure('bad-request', 'Invalid replay target', 'The replay target is invalid.'),
        );
      }
      const event = await dependencies.operations.event(active.value.authorization, landscape, eventId);
      if (!event.ok) {
        return renderActiveFailure(context, requestNonce, active.value.ticket, event.error);
      }
      return html(
        context,
        requestNonce,
        renderConfirmation({
          nonce: requestNonce,
          identity: active.value.ticket.identity,
          csrfToken: active.value.ticket.csrfToken,
          kind,
          event: event.value,
          selectedEndpointId,
        }),
      );
    }

    const landscape = context.req.param('landscape');
    const endpointId = context.req.param('endpointId');
    if (
      !validIdentifier(landscape) ||
      !validIdentifier(endpointId) ||
      !inScope(active.value.authorization.scope.landscapes, landscape)
    ) {
      return renderActiveFailure(
        context,
        requestNonce,
        active.value.ticket,
        failure('bad-request', 'Invalid endpoint target', 'The endpoint reference is invalid.'),
      );
    }
    const endpoint = await dependencies.operations.endpoint(active.value.authorization, landscape, endpointId);
    if (!endpoint.ok) {
      return renderActiveFailure(context, requestNonce, active.value.ticket, endpoint.error);
    }
    return html(
      context,
      requestNonce,
      renderConfirmation({
        nonce: requestNonce,
        identity: active.value.ticket.identity,
        csrfToken: active.value.ticket.csrfToken,
        kind,
        endpoint: endpoint.value,
      }),
    );
  };

  app.get('/console/events/:landscape/:eventId/replay', context =>
    confirmation(context, 'replay-event', 'events:replay'),
  );
  app.get('/console/endpoints/:landscape/:endpointId/replay', context =>
    confirmation(context, 'replay-endpoint', 'endpoints:replay'),
  );
  app.get('/console/endpoints/:landscape/:endpointId/reenable', context =>
    confirmation(context, 'reenable-endpoint', 'endpoints:reenable'),
  );

  type ActionName = 'replay-event' | 'replay-endpoint' | 'reenable-endpoint';
  const executeAction = async (
    context: Context,
    action: ActionName,
    capability: ConsoleCapability,
    expectedConfirmation: string,
  ): Promise<Response> => {
    const requestNonce = nonce();
    const active = await activeRequest(context, ['operations:read', capability]);
    if (!active.ok) {
      return renderInactive(context, requestNonce, active);
    }
    const mutation = await requireMutation(context, active.value.ticket);
    if (!mutation.ok) {
      return renderActiveFailure(context, requestNonce, active.value.ticket, mutation.error);
    }
    const submittedConfirmation = singleField(mutation.value, 'confirmation', 3, 32);
    const reason = singleField(mutation.value, 'reason', 3, 240);
    if (
      !submittedConfirmation.ok ||
      !dependencies.requestSecurity.equal(submittedConfirmation.value, expectedConfirmation) ||
      !reason.ok
    ) {
      return renderActiveFailure(
        context,
        requestNonce,
        active.value.ticket,
        failure(
          'bad-request',
          'Confirmation did not match',
          'Type the exact confirmation phrase and provide an audit reason.',
        ),
      );
    }

    const audit = {
      requestId: dependencies.requestSecurity.issueToken(16),
      sessionId: active.value.ticket.sessionId,
      accountId: active.value.ticket.identity.accountId,
      reason: reason.value,
    };

    let result: Awaited<ReturnType<ConsoleOperations['replayEvent']>>;
    if (action === 'replay-event') {
      const landscape = context.req.param('landscape');
      const eventId = context.req.param('eventId');
      const endpointId = context.req.query('endpoint');
      if (
        !validIdentifier(landscape) ||
        !validIdentifier(eventId) ||
        (endpointId !== undefined && !validIdentifier(endpointId)) ||
        !inScope(active.value.authorization.scope.landscapes, landscape)
      ) {
        return renderActiveFailure(
          context,
          requestNonce,
          active.value.ticket,
          failure('bad-request', 'Invalid replay target', 'The replay target is invalid.'),
        );
      }
      result = await dependencies.operations.replayEvent(active.value.authorization, {
        landscape,
        eventId,
        endpointId,
        audit,
      });
    } else {
      const landscape = context.req.param('landscape');
      const endpointId = context.req.param('endpointId');
      if (
        !validIdentifier(landscape) ||
        !validIdentifier(endpointId) ||
        !inScope(active.value.authorization.scope.landscapes, landscape)
      ) {
        return renderActiveFailure(
          context,
          requestNonce,
          active.value.ticket,
          failure('bad-request', 'Invalid endpoint target', 'The endpoint reference is invalid.'),
        );
      }
      result =
        action === 'replay-endpoint'
          ? await dependencies.operations.replayEndpoint(active.value.authorization, {
              landscape,
              endpointId,
              audit,
            })
          : await dependencies.operations.reenableEndpoint(active.value.authorization, {
              landscape,
              endpointId,
              audit,
            });
    }
    if (!result.ok && result.error.retryAfterSeconds !== undefined) {
      context.header('Retry-After', String(result.error.retryAfterSeconds));
    }
    return html(
      context,
      requestNonce,
      renderOutcome({
        nonce: requestNonce,
        identity: active.value.ticket.identity,
        csrfToken: active.value.ticket.csrfToken,
        receipt: result.ok ? result.value : undefined,
        failure: result.ok ? undefined : result.error,
      }),
      result.ok ? 200 : failureStatus(result.error),
    );
  };

  app.post('/console/events/:landscape/:eventId/replay', context =>
    executeAction(context, 'replay-event', 'events:replay', 'REPLAY EVENT'),
  );
  app.post('/console/endpoints/:landscape/:endpointId/replay', context =>
    executeAction(context, 'replay-endpoint', 'endpoints:replay', 'REPLAY ENDPOINT'),
  );
  app.post('/console/endpoints/:landscape/:endpointId/reenable', context =>
    executeAction(context, 'reenable-endpoint', 'endpoints:reenable', 'REENABLE'),
  );

  const notFound = (context: Context): Response => {
    const requestNonce = nonce();
    return html(
      context,
      requestNonce,
      renderPublicFailure({
        nonce: requestNonce,
        title: 'Console route not found',
        detail: 'The requested console route does not exist.',
      }),
      404,
    );
  };
  app.all('/console', notFound);
  app.all('/console/*', notFound);

  app.onError(async (error, context) => {
    const requestId = dependencies.requestSecurity.issueToken(16);
    const requestNonce = nonce();
    await dependencies.incidentReporter
      .report({
        requestId,
        method: context.req.method,
        path: new URL(context.req.url).pathname,
        error,
      })
      .catch(() => undefined);
    context.header('X-Request-ID', requestId);
    return html(
      context,
      requestNonce,
      renderPublicFailure({
        nonce: requestNonce,
        title: 'Console operation interrupted',
        detail: 'Mercury could not complete this request. No control action was assumed.',
        requestId,
      }),
      500,
    );
  });

  return app;
};
