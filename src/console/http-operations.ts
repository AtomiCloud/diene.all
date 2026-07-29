import {
  type LocalLandscapeActionReceipt,
  type LocalLandscapeDeadLetter,
  type LocalLandscapeDeadLetterList,
  type LocalLandscapeEventDetail,
  type LocalLandscapeEventList,
  type LocalLandscapeEventSummary,
  type LocalLandscapeHealth,
  parseLocalLandscapeActionReceipt,
  parseLocalLandscapeDeadLetterList,
  parseLocalLandscapeEventDetail,
  parseLocalLandscapeEventList,
  parseLocalLandscapeHealth,
} from './landscape-dto.ts';
import type {
  ConsoleActionAudit,
  ConsoleActionReceipt,
  ConsoleActionTarget,
  ConsoleAuthorizationScope,
  ConsoleCapability,
  ConsoleDashboardSnapshot,
  ConsoleDeadLetter,
  ConsoleDeliveryHealth,
  ConsoleEndpointReplayTarget,
  ConsoleEventDetail,
  ConsoleEventStatus,
  ConsoleEventSummary,
  ConsoleFailure,
  ConsoleFilterOption,
  ConsoleFilters,
  ConsoleLandscapeFailure,
  ConsoleLandscapeSource,
  ConsoleNativeAuthorization,
  ConsolePreviewVisibility,
  ConsoleResult,
  ConsoleRouteState,
} from './model.ts';
import type {
  ConsoleActionAuditor,
  ConsoleClock,
  ConsoleManagementAccountGateway,
  ConsoleOperations,
} from './ports.ts';

const DEFAULT_TIMEOUT_MILLISECONDS = 2_000;
const DEFAULT_MAX_CONCURRENCY = 8;
const DEFAULT_MAX_RESPONSE_BYTES = 3 * 1_024 * 1_024;
const DEFAULT_MAX_FAN_IN_REQUESTS = 512;
const DEFAULT_EVENT_LIMIT = 200;
const MAX_AUTHORIZATION_BYTES = 8_192;

type ConsoleFetch = typeof globalThis.fetch;

interface HttpClientConfiguration {
  readonly clock: ConsoleClock;
  readonly fetch: ConsoleFetch;
  readonly timeoutMilliseconds: number;
  readonly maxConcurrency: number;
  readonly maxResponseBytes: number;
  readonly maxFanInRequests: number;
  readonly eventLimit: number;
  readonly previewVisibility: ConsolePreviewVisibility;
}

export interface HttpConsoleOperationsOptions {
  readonly clock: ConsoleClock;
  readonly fetch?: ConsoleFetch;
  readonly timeoutMilliseconds?: number;
  readonly maxConcurrency?: number;
  readonly maxResponseBytes?: number;
  readonly maxFanInRequests?: number;
  readonly eventLimit?: number;
  readonly previewVisibility?: ConsolePreviewVisibility;
}

const failure = (
  kind: ConsoleFailure['kind'],
  title: string,
  detail: string,
  retryAfterSeconds?: number,
): ConsoleResult<never> => ({
  ok: false,
  error: { kind, title, detail, ...(retryAfterSeconds === undefined ? {} : { retryAfterSeconds }) },
});

const remoteFailure = (response: Response, operation: string): ConsoleResult<never> => {
  const retryAfter = Number(response.headers.get('retry-after'));
  const retryAfterSeconds =
    Number.isSafeInteger(retryAfter) && retryAfter > 0 && retryAfter <= 86_400 ? retryAfter : undefined;
  const kind: ConsoleFailure['kind'] =
    response.status === 400
      ? 'bad-request'
      : response.status === 401
        ? 'unauthenticated'
        : response.status === 403
          ? 'forbidden'
          : response.status === 404
            ? 'not-found'
            : response.status === 409
              ? 'conflict'
              : response.status === 429
                ? 'rate-limited'
                : 'unavailable';
  return failure(
    kind,
    kind === 'not-found' ? 'Landscape resource not found' : 'Landscape operation rejected',
    `The authenticated landscape ${operation} request could not be completed.`,
    retryAfterSeconds,
  );
};

const validPositiveInteger = (value: number, maximum: number): boolean =>
  Number.isSafeInteger(value) && value > 0 && value <= maximum;

const copyPreviewVisibility = (value: ConsolePreviewVisibility): ConsolePreviewVisibility => ({
  state: value.state,
  detail: value.detail,
  affectedLandscapes: [...value.affectedLandscapes],
});

const createConfiguration = (options: HttpConsoleOperationsOptions): HttpClientConfiguration => {
  const timeoutMilliseconds = options.timeoutMilliseconds ?? DEFAULT_TIMEOUT_MILLISECONDS;
  const maxConcurrency = options.maxConcurrency ?? DEFAULT_MAX_CONCURRENCY;
  const maxResponseBytes = options.maxResponseBytes ?? DEFAULT_MAX_RESPONSE_BYTES;
  const maxFanInRequests = options.maxFanInRequests ?? DEFAULT_MAX_FAN_IN_REQUESTS;
  const eventLimit = options.eventLimit ?? DEFAULT_EVENT_LIMIT;
  const previewVisibility = options.previewVisibility ?? {
    state: 'visible',
    detail: 'Preview callback-delivery visibility is available for enabled landscape sources.',
    affectedLandscapes: [],
  };
  if (
    !validPositiveInteger(timeoutMilliseconds, 30_000) ||
    !validPositiveInteger(maxConcurrency, 64) ||
    !validPositiveInteger(maxResponseBytes, 8 * 1_024 * 1_024) ||
    !validPositiveInteger(maxFanInRequests, 4_096) ||
    !validPositiveInteger(eventLimit, 200) ||
    previewVisibility.detail.length === 0 ||
    previewVisibility.detail.length > 2_048
  ) {
    throw new Error('Console HTTP operations configuration is invalid');
  }
  return {
    clock: options.clock,
    fetch: options.fetch ?? globalThis.fetch,
    timeoutMilliseconds,
    maxConcurrency,
    maxResponseBytes,
    maxFanInRequests,
    eventLimit,
    previewVisibility: copyPreviewVisibility(previewVisibility),
  };
};

const operationUrl = (
  base: string,
  segments: readonly string[],
  query?: Readonly<Record<string, string | undefined>>,
): URL => {
  const url = new URL(base);
  const basePath = url.pathname.replace(/\/+$/, '');
  url.pathname = `${basePath}/${segments.map(segment => encodeURIComponent(segment)).join('/')}`;
  url.search = '';
  url.hash = '';
  if (query !== undefined) {
    for (const [name, value] of Object.entries(query)) {
      if (value !== undefined) url.searchParams.set(name, value);
    }
  }
  return url;
};

const readBoundedBody = async (
  body: ReadableStream<Uint8Array> | null,
  maximumBytes: number,
): Promise<Uint8Array | undefined> => {
  if (body === null) return new Uint8Array();
  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let byteLength = 0;
  while (true) {
    const next = await reader.read();
    if (next.done) break;
    byteLength += next.value.byteLength;
    if (byteLength > maximumBytes) {
      await reader.cancel();
      return undefined;
    }
    chunks.push(next.value);
  }
  const bytes = new Uint8Array(byteLength);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
};

const requestJson = async (
  configuration: HttpClientConfiguration,
  authorization: ConsoleNativeAuthorization,
  url: URL,
  expectedOrigin: string,
  operation: string,
  method: 'GET' | 'POST' = 'GET',
  body?: unknown,
): Promise<ConsoleResult<unknown>> => {
  if (url.protocol !== 'https:' || url.origin !== expectedOrigin) {
    return failure(
      'unavailable',
      'Landscape source rejected',
      `The authenticated landscape ${operation} request did not match its trusted origin.`,
    );
  }
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), configuration.timeoutMilliseconds);
  try {
    const response = await configuration.fetch(url, {
      method,
      headers: {
        Accept: 'application/json',
        Authorization: `Bearer ${authorization.token}`,
        ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      cache: 'no-store',
      credentials: 'omit',
      redirect: 'error',
      referrerPolicy: 'no-referrer',
      signal: controller.signal,
    });
    if (!response.ok) {
      await response.body?.cancel();
      return remoteFailure(response, operation);
    }
    const contentType = response.headers.get('content-type')?.split(';', 1)[0]?.trim().toLowerCase();
    if (contentType !== 'application/json' && contentType !== 'application/problem+json') {
      await response.body?.cancel();
      return failure(
        'unavailable',
        'Landscape response rejected',
        `The authenticated landscape ${operation} response was not JSON.`,
      );
    }
    const declaredLength = Number(response.headers.get('content-length'));
    if (Number.isFinite(declaredLength) && declaredLength > configuration.maxResponseBytes) {
      await response.body?.cancel();
      return failure(
        'unavailable',
        'Landscape response rejected',
        `The authenticated landscape ${operation} response exceeded the size limit.`,
      );
    }
    const bytes = await readBoundedBody(response.body, configuration.maxResponseBytes);
    if (bytes === undefined) {
      return failure(
        'unavailable',
        'Landscape response rejected',
        `The authenticated landscape ${operation} response exceeded the size limit.`,
      );
    }
    try {
      return { ok: true, value: JSON.parse(new TextDecoder().decode(bytes)) as unknown };
    } catch {
      return failure(
        'unavailable',
        'Landscape response rejected',
        `The authenticated landscape ${operation} response contained invalid JSON.`,
      );
    }
  } catch {
    return failure(
      'unavailable',
      'Landscape source unavailable',
      `The authenticated landscape ${operation} request timed out or could not connect.`,
    );
  } finally {
    clearTimeout(timeout);
  }
};

const parseResponse = <Value>(
  response: ConsoleResult<unknown>,
  parser: (input: unknown) => ConsoleResult<Value>,
): ConsoleResult<Value> => (response.ok ? parser(response.value) : response);

const readHealth = async (
  configuration: HttpClientConfiguration,
  source: ConsoleLandscapeSource,
  authorization: ConsoleNativeAuthorization,
): Promise<ConsoleResult<LocalLandscapeHealth>> =>
  parseResponse(
    await requestJson(
      configuration,
      authorization,
      operationUrl(source.queryUrl, ['health']),
      source.queryOrigin,
      'health',
    ),
    parseLocalLandscapeHealth,
  );

const readEvents = async (
  configuration: HttpClientConfiguration,
  source: ConsoleLandscapeSource,
  authorization: ConsoleNativeAuthorization,
  tenant: string,
  query: Readonly<Record<string, string | undefined>> = {},
): Promise<ConsoleResult<LocalLandscapeEventList>> =>
  parseResponse(
    await requestJson(
      configuration,
      authorization,
      operationUrl(source.queryUrl, ['tenants', tenant, 'events'], {
        ...query,
        limit: String(configuration.eventLimit),
      }),
      source.queryOrigin,
      'event-list',
    ),
    parseLocalLandscapeEventList,
  );

const readEventDetail = async (
  configuration: HttpClientConfiguration,
  source: ConsoleLandscapeSource,
  authorization: ConsoleNativeAuthorization,
  tenant: string,
  eventId: string,
): Promise<ConsoleResult<LocalLandscapeEventDetail>> =>
  parseResponse(
    await requestJson(
      configuration,
      authorization,
      operationUrl(source.queryUrl, ['tenants', tenant, 'events', eventId]),
      source.queryOrigin,
      'event-detail',
    ),
    parseLocalLandscapeEventDetail,
  );

const readDeadLetters = async (
  configuration: HttpClientConfiguration,
  source: ConsoleLandscapeSource,
  authorization: ConsoleNativeAuthorization,
  tenant: string,
): Promise<ConsoleResult<LocalLandscapeDeadLetterList>> =>
  parseResponse(
    await requestJson(
      configuration,
      authorization,
      operationUrl(source.queryUrl, ['tenants', tenant, 'dlq']),
      source.queryOrigin,
      'dead-letter-list',
    ),
    parseLocalLandscapeDeadLetterList,
  );

const sendAction = async (
  configuration: HttpClientConfiguration,
  source: ConsoleLandscapeSource,
  authorization: ConsoleNativeAuthorization,
  segments: readonly string[],
  body: unknown,
): Promise<ConsoleResult<LocalLandscapeActionReceipt>> =>
  parseResponse(
    await requestJson(
      configuration,
      authorization,
      operationUrl(source.replayUrl, segments),
      source.replayOrigin,
      'action',
      'POST',
      body,
    ),
    parseLocalLandscapeActionReceipt,
  );

const mapLimited = async <Value>(
  tasks: readonly (() => Promise<Value>)[],
  concurrency: number,
): Promise<readonly Value[]> => {
  const values = new Array<Value>(tasks.length);
  let nextIndex = 0;
  const workers = Array.from({ length: Math.min(concurrency, tasks.length) }, async () => {
    while (nextIndex < tasks.length) {
      const index = nextIndex;
      nextIndex += 1;
      const task = tasks[index];
      if (task !== undefined) values[index] = await task();
    }
  });
  await Promise.all(workers);
  return values;
};

const scopeIncludes = (scope: '*' | readonly string[], value: string): boolean =>
  scope === '*' || scope.includes(value);

const authorizationFailure = (
  configuration: HttpClientConfiguration,
  authorization: ConsoleNativeAuthorization,
  capability: ConsoleCapability,
  landscape?: string,
): ConsoleResult<never> | undefined => {
  const now = configuration.clock.now();
  if (
    authorization.scheme !== 'Bearer' ||
    authorization.token.length < 16 ||
    authorization.token.length > MAX_AUTHORIZATION_BYTES ||
    authorization.expiresAt.getTime() <= now.getTime()
  ) {
    return failure(
      'unauthenticated',
      'Native authorization expired',
      'The short-lived native authorization is invalid or expired.',
    );
  }
  if (
    !authorization.scope.capabilities.includes(capability) ||
    (landscape !== undefined && !scopeIncludes(authorization.scope.landscapes, landscape))
  ) {
    return failure(
      'forbidden',
      'Native authorization scope rejected',
      'The short-lived native authorization does not cover this operation.',
    );
  }
  return undefined;
};

const authorizedTenants = (scope: ConsoleAuthorizationScope): ConsoleResult<readonly string[]> =>
  scope.tenants === '*'
    ? failure(
        'forbidden',
        'Bounded tenant scope required',
        'Console fan-in requires an explicit account-scoped tenant set.',
      )
    : { ok: true, value: [...new Set(scope.tenants)].sort() };

const loadSources = async (
  gateway: ConsoleManagementAccountGateway,
  authorization: ConsoleNativeAuthorization,
): Promise<ConsoleResult<readonly ConsoleLandscapeSource[]>> => {
  const loaded = await gateway.landscapeSources({
    accountId: authorization.accountId,
    authorization,
  });
  if (!loaded.ok) return loaded;
  const trustedSource = (source: ConsoleLandscapeSource): boolean => {
    if (source.trustKind !== 'account-owned' || source.accountId !== authorization.accountId) return false;
    try {
      const query = new URL(source.queryUrl);
      const replay = new URL(source.replayUrl);
      return (
        query.protocol === 'https:' &&
        replay.protocol === 'https:' &&
        query.username === '' &&
        query.password === '' &&
        query.port === '' &&
        replay.username === '' &&
        replay.password === '' &&
        replay.port === '' &&
        query.search === '' &&
        query.hash === '' &&
        replay.search === '' &&
        replay.hash === '' &&
        query.href === source.queryUrl &&
        replay.href === source.replayUrl &&
        query.origin === source.queryOrigin &&
        replay.origin === source.replayOrigin
      );
    } catch {
      return false;
    }
  };
  if (loaded.value.some(source => !trustedSource(source))) {
    return failure(
      'unavailable',
      'Landscape source configuration rejected',
      'Every landscape operation source must match the signed account and its trusted HTTPS origin binding.',
    );
  }
  const sources = loaded.value
    .filter(source => source.enabled && scopeIncludes(authorization.scope.landscapes, source.landscape))
    .sort((left, right) => left.landscape.localeCompare(right.landscape));
  if (sources.length === 0) {
    return failure(
      'unavailable',
      'No landscape sources enabled',
      'This account has no enabled landscape operations sources.',
    );
  }
  if (new Set(sources.map(source => source.landscape)).size !== sources.length) {
    return failure(
      'unavailable',
      'Landscape source configuration rejected',
      'Enabled landscape operation sources must be unique by landscape.',
    );
  }
  return { ok: true, value: sources };
};

const selectedSource = async (
  gateway: ConsoleManagementAccountGateway,
  authorization: ConsoleNativeAuthorization,
  landscape: string,
): Promise<ConsoleResult<ConsoleLandscapeSource>> => {
  const sources = await loadSources(gateway, authorization);
  if (!sources.ok) return sources;
  const source = sources.value.find(candidate => candidate.landscape === landscape);
  return source === undefined
    ? failure('not-found', 'Landscape source not found', 'The selected landscape operations source is not enabled.')
    : { ok: true, value: source };
};

const redact = (value: string, authorization: ConsoleNativeAuthorization): string =>
  value.includes(authorization.token) ? value.replaceAll(authorization.token, '[REDACTED AUTHORIZATION]') : value;

const eventStatusValue = (status: LocalLandscapeEventSummary['status']): Exclude<ConsoleEventStatus, 'all'> => {
  switch (status) {
    case 'completed':
      return 'delivered';
    case 'dead-letter':
      return 'dead-lettered';
    case 'paused':
      return 'withheld';
    case 'pending':
      return 'queued';
    case 'retrying':
      return 'retrying';
  }
};

const eventRows = (
  event: LocalLandscapeEventSummary,
  now: Date,
  authorization: ConsoleNativeAuthorization,
): readonly ConsoleEventSummary[] => {
  const endpoints = event.endpointIds.length === 0 ? ['unassigned'] : event.endpointIds;
  return endpoints.map(endpointId => ({
    id: redact(event.id, authorization),
    landscape: redact(event.landscape, authorization),
    tenant: redact(event.tenantId, authorization),
    provider: redact(event.provider, authorization),
    route: redact(event.routeId, authorization),
    endpointId: redact(endpointId, authorization),
    endpointName: redact(endpointId, authorization),
    status: eventStatusValue(event.status),
    receivedAt: new Date(event.receivedAtMs),
    ...(event.providerTimestampMs === undefined ? {} : { providerTimestamp: new Date(event.providerTimestampMs) }),
    ...(event.providerSequence === undefined
      ? {}
      : { providerSequence: redact(event.providerSequence, authorization) }),
    attemptCount: event.attemptCount,
    ...(event.nextDueAtMs === undefined ? {} : { nextAttemptAt: new Date(event.nextDueAtMs) }),
    lagSeconds: Math.max(0, Math.floor((now.getTime() - event.receivedAtMs) / 1_000)),
  }));
};

const deadLetterValue = (
  item: LocalLandscapeDeadLetter,
  authorization: ConsoleNativeAuthorization,
): ConsoleDeadLetter => ({
  eventId: redact(item.eventId, authorization),
  landscape: redact(item.landscape, authorization),
  tenant: redact(item.tenantId, authorization),
  provider: redact(item.provider ?? 'unknown', authorization),
  endpointId: redact(item.endpointId, authorization),
  endpointName: redact(item.endpointId, authorization),
  exhaustedAt: new Date(item.exhaustedAtMs),
  finalStatus:
    typeof item.finalOutcome === 'number'
      ? item.finalOutcome
      : item.finalOutcome?.toLowerCase().includes('timeout') === true
        ? 'timeout'
        : 'network-error',
  attempts: item.attemptCount,
});

const matchesFilters = (event: ConsoleEventSummary, filters: ConsoleFilters): boolean =>
  (filters.landscape === undefined || event.landscape === filters.landscape) &&
  (filters.tenant === undefined || event.tenant === filters.tenant) &&
  (filters.provider === undefined || event.provider === filters.provider) &&
  (filters.endpoint === undefined || event.endpointId === filters.endpoint) &&
  (filters.status === 'all' || event.status === filters.status);

const deadLetterMatchesFilters = (item: ConsoleDeadLetter, filters: ConsoleFilters): boolean =>
  (filters.landscape === undefined || item.landscape === filters.landscape) &&
  (filters.tenant === undefined || item.tenant === filters.tenant) &&
  (filters.provider === undefined || item.provider === filters.provider) &&
  (filters.endpoint === undefined || item.endpointId === filters.endpoint) &&
  (filters.status === 'all' || filters.status === 'dead-lettered');

const optionsFrom = (values: readonly string[]): readonly ConsoleFilterOption[] => {
  const counts = new Map<string, number>();
  for (const value of values) counts.set(value, (counts.get(value) ?? 0) + 1);
  return [...counts]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([value, count]) => ({ value, label: value, count }));
};

const deliveryHealth = (
  events: readonly ConsoleEventSummary[],
  deadLetters: readonly ConsoleDeadLetter[],
): readonly ConsoleDeliveryHealth[] => {
  const groups = new Map<string, ConsoleEventSummary[]>();
  for (const event of events) {
    const key = [event.landscape, event.tenant, event.provider, event.endpointId].join('\0');
    const group = groups.get(key) ?? [];
    group.push(event);
    groups.set(key, group);
  }
  return [...groups.values()]
    .map(group => {
      const first = group[0];
      if (first === undefined) throw new Error('Console delivery group cannot be empty');
      const delivered = group.filter(event => event.status === 'delivered').length;
      const deadLetterCount = deadLetters.filter(
        item =>
          item.landscape === first.landscape &&
          item.tenant === first.tenant &&
          item.provider === first.provider &&
          item.endpointId === first.endpointId,
      ).length;
      const paused = group.some(event => event.status === 'withheld');
      const unhealthy = group.some(event => ['queued', 'retrying', 'dead-lettered', 'withheld'].includes(event.status));
      return {
        endpointId: first.endpointId,
        endpointName: first.endpointName,
        tenant: first.tenant,
        provider: first.provider,
        landscape: first.landscape,
        state: deadLetterCount > 0 ? 'critical' : unhealthy ? 'degraded' : 'healthy',
        circuit: paused ? 'open' : 'closed',
        successRate: group.length === 0 ? 0 : delivered / group.length,
        retryDepth: group.filter(event => event.status === 'queued' || event.status === 'retrying').length,
        lagSeconds: Math.max(...group.map(event => event.lagSeconds)),
        deadLetterCount,
        canReenable: paused,
      } satisfies ConsoleDeliveryHealth;
    })
    .sort((left, right) =>
      [left.landscape, left.tenant, left.endpointId]
        .join('\0')
        .localeCompare([right.landscape, right.tenant, right.endpointId].join('\0')),
    );
};

const routeState = (
  events: readonly ConsoleEventSummary[],
  generations: ReadonlyMap<string, number>,
): readonly ConsoleRouteState[] => {
  const groups = new Map<string, ConsoleEventSummary[]>();
  for (const event of events) {
    const key = [event.landscape, event.tenant, event.provider, event.route].join('\0');
    const group = groups.get(key) ?? [];
    group.push(event);
    groups.set(key, group);
  }
  return [...groups.values()]
    .map(group => {
      const first = group[0];
      if (first === undefined) throw new Error('Console route group cannot be empty');
      return {
        routeId: first.route,
        route: first.route,
        tenant: first.tenant,
        provider: first.provider,
        landscape: first.landscape,
        endpointCount: new Set(group.map(event => event.endpointId)).size,
        state: 'active',
        activeGeneration: generations.get(first.landscape) ?? 0,
      } satisfies ConsoleRouteState;
    })
    .sort((left, right) =>
      [left.landscape, left.tenant, left.route]
        .join('\0')
        .localeCompare([right.landscape, right.tenant, right.route].join('\0')),
    );
};

type DashboardLoad =
  | {
      readonly kind: 'health';
      readonly source: ConsoleLandscapeSource;
      readonly result: ConsoleResult<LocalLandscapeHealth>;
    }
  | {
      readonly kind: 'events';
      readonly source: ConsoleLandscapeSource;
      readonly tenant: string;
      readonly result: ConsoleResult<LocalLandscapeEventList>;
    }
  | {
      readonly kind: 'dead-letters';
      readonly source: ConsoleLandscapeSource;
      readonly tenant: string;
      readonly result: ConsoleResult<LocalLandscapeDeadLetterList>;
    };

const sourceFailure = (
  landscape: string,
  operation: ConsoleLandscapeFailure['operation'],
  error: ConsoleFailure,
): ConsoleLandscapeFailure => ({
  landscape,
  operation,
  kind: error.kind,
  detail: error.detail,
});

const auditBody = (audit: ConsoleActionAudit): { readonly audit: ConsoleActionAudit } => ({
  audit: {
    requestId: audit.requestId,
    sessionId: audit.sessionId,
    accountId: audit.accountId,
    reason: audit.reason,
  },
});

const auditAction = async (
  auditor: ConsoleActionAuditor,
  authorization: ConsoleNativeAuthorization,
  tenantId: string,
  landscape: string,
  target: ConsoleActionTarget,
  context: ConsoleActionAudit,
): Promise<ConsoleResult<void>> => {
  if (
    context.accountId !== authorization.accountId ||
    context.sessionId !== authorization.sessionId ||
    !scopeIncludes(authorization.scope.tenants, tenantId) ||
    !scopeIncludes(authorization.scope.landscapes, landscape)
  ) {
    return failure(
      'forbidden',
      'Action audit context rejected',
      'The action audit context did not match the verified native authorization.',
    );
  }
  try {
    return await auditor.accept({
      authorization: {
        sessionId: authorization.sessionId,
        accountId: authorization.accountId,
        expiresAt: new Date(authorization.expiresAt),
        scope: {
          tenants: authorization.scope.tenants === '*' ? '*' : [...authorization.scope.tenants],
          landscapes: authorization.scope.landscapes === '*' ? '*' : [...authorization.scope.landscapes],
          capabilities: [...authorization.scope.capabilities],
        },
      },
      tenantId,
      landscape,
      target,
      context: { ...context },
    });
  } catch {
    return failure(
      'unavailable',
      'Action audit unavailable',
      'The action was not dispatched because its durable audit could not be accepted.',
    );
  }
};

interface LocatedEvent {
  readonly tenant: string;
  readonly detail: LocalLandscapeEventDetail;
}

const locateEvent = async (
  configuration: HttpClientConfiguration,
  source: ConsoleLandscapeSource,
  authorization: ConsoleNativeAuthorization,
  tenants: readonly string[],
  eventId: string,
): Promise<ConsoleResult<LocatedEvent>> => {
  if (tenants.length > configuration.maxFanInRequests) {
    return failure(
      'unavailable',
      'Fan-in request budget exceeded',
      'The account tenant scope exceeds the bounded event lookup budget.',
    );
  }
  const results = await mapLimited(
    tenants.map(tenant => async () => ({
      tenant,
      result: await readEventDetail(configuration, source, authorization, tenant, eventId),
    })),
    configuration.maxConcurrency,
  );
  const matches = results.filter(
    (
      value,
    ): value is {
      readonly tenant: string;
      readonly result: { readonly ok: true; readonly value: LocalLandscapeEventDetail };
    } =>
      value.result.ok &&
      value.result.value.event.id === eventId &&
      value.result.value.event.tenantId === value.tenant &&
      value.result.value.event.landscape === source.landscape,
  );
  if (matches.length > 1) {
    return failure(
      'conflict',
      'Ambiguous retained event',
      'The retained event reference matched more than one authorized tenant.',
    );
  }
  const match = matches[0];
  if (match !== undefined) return { ok: true, value: { tenant: match.tenant, detail: match.result.value } };
  const rejected = results.find(value => !value.result.ok && value.result.error.kind !== 'not-found');
  return rejected !== undefined && !rejected.result.ok
    ? rejected.result
    : failure('not-found', 'Retained event not found', 'The retained event was not found in this landscape.');
};

const displayPayload = (base64: string, authorization: ConsoleNativeAuthorization): string => {
  const bytes = Buffer.from(base64, 'base64');
  try {
    return redact(new TextDecoder('utf-8', { fatal: true }).decode(bytes), authorization);
  } catch {
    return `[base64]\n${redact(base64, authorization)}`;
  }
};

const visibleHeaders = (
  headers: Readonly<Record<string, string>>,
  authorization: ConsoleNativeAuthorization,
): Readonly<Record<string, string>> =>
  Object.fromEntries(
    Object.entries(headers)
      .filter(([name]) => !/^(?:authorization|cookie|proxy-authorization|set-cookie)$/i.test(name))
      .map(([name, value]) => [redact(name, authorization), redact(value, authorization)]),
  );

const eventDetailValue = (
  detail: LocalLandscapeEventDetail,
  configuration: HttpClientConfiguration,
  authorization: ConsoleNativeAuthorization,
): ConsoleEventDetail => {
  const job = detail.jobs[0];
  const endpointId = job?.endpointId ?? detail.event.endpointIds[0] ?? 'unassigned';
  const attempts = detail.jobs.flatMap(candidate => candidate.attempts);
  const lastAttempt = attempts.sort((left, right) => left.attemptedAtMs - right.attemptedAtMs).at(-1);
  return {
    id: redact(detail.event.id, authorization),
    landscape: redact(detail.event.landscape, authorization),
    tenant: redact(detail.event.tenantId, authorization),
    provider: redact(detail.event.provider, authorization),
    route: redact(detail.event.routeId, authorization),
    endpointId: redact(endpointId, authorization),
    endpointName: redact(endpointId, authorization),
    status: eventStatusValue(detail.event.status),
    receivedAt: new Date(detail.event.receivedAtMs),
    ...(detail.event.providerTimestampMs === undefined
      ? {}
      : { providerTimestamp: new Date(detail.event.providerTimestampMs) }),
    ...(detail.event.providerSequence === undefined
      ? {}
      : { providerSequence: redact(detail.event.providerSequence, authorization) }),
    attemptCount: detail.event.attemptCount,
    ...(detail.event.nextDueAtMs === undefined ? {} : { nextAttemptAt: new Date(detail.event.nextDueAtMs) }),
    lagSeconds: Math.max(0, Math.floor((configuration.clock.now().getTime() - detail.event.receivedAtMs) / 1_000)),
    allowedHeaders: visibleHeaders(detail.headers, authorization),
    metadata: Object.fromEntries(
      Object.entries(detail.verificationMetadata).map(([name, value]) => [
        redact(name, authorization),
        redact(value, authorization),
      ]),
    ),
    payload: displayPayload(detail.rawBodyBase64, authorization),
    payloadMediaType: redact(detail.headers['content-type'] ?? 'application/octet-stream', authorization),
    deliveryAddress: redact(job?.address ?? 'No delivery obligation retained', authorization),
    ...(lastAttempt?.statusCode === undefined ? {} : { lastResponseStatus: lastAttempt.statusCode }),
    ...(lastAttempt?.transportError === undefined
      ? {}
      : { lastResponseBody: redact(lastAttempt.transportError, authorization) }),
  };
};

interface LocatedEndpoint {
  readonly target: ConsoleEndpointReplayTarget;
  readonly tenant: string;
}

type EndpointLoad =
  | {
      readonly kind: 'events';
      readonly tenant: string;
      readonly result: ConsoleResult<LocalLandscapeEventList>;
    }
  | {
      readonly kind: 'dead-letters';
      readonly tenant: string;
      readonly result: ConsoleResult<LocalLandscapeDeadLetterList>;
    };

const locateEndpoint = async (
  configuration: HttpClientConfiguration,
  source: ConsoleLandscapeSource,
  authorization: ConsoleNativeAuthorization,
  tenants: readonly string[],
  endpointId: string,
): Promise<ConsoleResult<LocatedEndpoint>> => {
  if (tenants.length * 2 > configuration.maxFanInRequests) {
    return failure(
      'unavailable',
      'Fan-in request budget exceeded',
      'The account tenant scope exceeds the bounded endpoint lookup budget.',
    );
  }
  const tasks: (() => Promise<EndpointLoad>)[] = tenants.flatMap(tenant => [
    async () => ({
      kind: 'events' as const,
      tenant,
      result: await readEvents(configuration, source, authorization, tenant, { endpointId }),
    }),
    async () => ({
      kind: 'dead-letters' as const,
      tenant,
      result: await readDeadLetters(configuration, source, authorization, tenant),
    }),
  ]);
  const loaded = await mapLimited(tasks, configuration.maxConcurrency);
  const candidates = tenants.flatMap(tenant => {
    const eventLoad = loaded.find(
      (value): value is Extract<EndpointLoad, { readonly kind: 'events' }> =>
        value.kind === 'events' && value.tenant === tenant,
    );
    const deadLetterLoad = loaded.find(
      (value): value is Extract<EndpointLoad, { readonly kind: 'dead-letters' }> =>
        value.kind === 'dead-letters' && value.tenant === tenant,
    );
    const events = eventLoad?.result.ok
      ? eventLoad.result.value.items.filter(item => item.endpointIds.includes(endpointId))
      : [];
    const deadLetters = deadLetterLoad?.result.ok
      ? deadLetterLoad.result.value.items.filter(item => item.endpointId === endpointId)
      : [];
    if (events.length === 0 && deadLetters.length === 0) return [];
    const timestamps = [...events.map(item => item.receivedAtMs), ...deadLetters.map(item => item.exhaustedAtMs)];
    return [
      {
        tenant,
        target: {
          endpointId: redact(endpointId, authorization),
          endpointName: redact(endpointId, authorization),
          tenant: redact(tenant, authorization),
          provider: redact(events[0]?.provider ?? deadLetters[0]?.provider ?? 'unknown', authorization),
          landscape: redact(source.landscape, authorization),
          circuit: events.some(item => item.status === 'paused') ? 'open' : 'closed',
          replayableEvents: deadLetters.length,
          ...(timestamps.length === 0 ? {} : { oldestEventAt: new Date(Math.min(...timestamps)) }),
        } satisfies ConsoleEndpointReplayTarget,
      },
    ];
  });
  if (candidates.length > 1) {
    return failure(
      'conflict',
      'Ambiguous endpoint reference',
      'The endpoint reference matched more than one authorized tenant.',
    );
  }
  const candidate = candidates[0];
  if (candidate !== undefined) return { ok: true, value: candidate };
  const rejected = loaded.find(value => !value.result.ok && value.result.error.kind !== 'not-found');
  return rejected !== undefined && !rejected.result.ok
    ? rejected.result
    : failure('not-found', 'Endpoint not found', 'The endpoint was not found in this landscape.');
};

const actionReceiptValue = (
  receipt: LocalLandscapeActionReceipt,
  expectedLandscape: string,
  expectedTenant: string,
  authorization: ConsoleNativeAuthorization,
): ConsoleResult<ConsoleActionReceipt> => {
  if (receipt.landscape !== expectedLandscape || receipt.tenantId !== expectedTenant) {
    return failure(
      'unavailable',
      'Landscape response rejected',
      'The action receipt did not match the selected landscape and tenant.',
    );
  }
  const title =
    receipt.action === 'event-replayed'
      ? 'Event replay accepted'
      : receipt.action === 'endpoint-replayed'
        ? 'Endpoint replay accepted'
        : 'Delivery circuit re-enabled';
  return {
    ok: true,
    value: {
      actionId: redact(receipt.actionId, authorization),
      title,
      detail: `${title} by the scoped landscape operations service.`,
      acceptedAt: new Date(receipt.acceptedAtMs),
      landscape: redact(receipt.landscape, authorization),
      affectedCount: receipt.affectedCount,
    },
  };
};

export class HttpConsoleOperations implements ConsoleOperations {
  readonly #gateway: ConsoleManagementAccountGateway;
  readonly #auditor: ConsoleActionAuditor;
  readonly #configuration: HttpClientConfiguration;

  constructor(
    gateway: ConsoleManagementAccountGateway,
    auditor: ConsoleActionAuditor,
    options: HttpConsoleOperationsOptions,
  ) {
    this.#gateway = gateway;
    this.#auditor = auditor;
    this.#configuration = createConfiguration(options);
  }

  async dashboard(
    authorization: ConsoleNativeAuthorization,
    filters: ConsoleFilters,
  ): Promise<ConsoleResult<ConsoleDashboardSnapshot>> {
    const rejected = authorizationFailure(this.#configuration, authorization, 'operations:read');
    if (rejected !== undefined) return rejected;
    const tenants = authorizedTenants(authorization.scope);
    if (!tenants.ok) return tenants;
    const loadedSources = await loadSources(this.#gateway, authorization);
    if (!loadedSources.ok) return loadedSources;
    const sources = loadedSources.value.filter(
      source => filters.landscape === undefined || source.landscape === filters.landscape,
    );
    const selectedTenants = tenants.value.filter(tenant => filters.tenant === undefined || tenant === filters.tenant);
    const requestCount = sources.length * (1 + selectedTenants.length * 2);
    if (requestCount > this.#configuration.maxFanInRequests) {
      return failure(
        'unavailable',
        'Fan-in request budget exceeded',
        'The selected account scope exceeds the bounded landscape request budget.',
      );
    }

    const tasks: (() => Promise<DashboardLoad>)[] = sources.flatMap(source => [
      async () => ({
        kind: 'health' as const,
        source,
        result: await readHealth(this.#configuration, source, authorization),
      }),
      ...selectedTenants.flatMap(tenant => [
        async () => ({
          kind: 'events' as const,
          source,
          tenant,
          result: await readEvents(this.#configuration, source, authorization, tenant),
        }),
        async () => ({
          kind: 'dead-letters' as const,
          source,
          tenant,
          result: await readDeadLetters(this.#configuration, source, authorization, tenant),
        }),
      ]),
    ]);
    const loads = await mapLimited(tasks, this.#configuration.maxConcurrency);
    const sourceFailures: ConsoleLandscapeFailure[] = [];
    const health: LocalLandscapeHealth[] = [];
    const retainedEvents: LocalLandscapeEventSummary[] = [];
    const retainedDeadLetters: LocalLandscapeDeadLetter[] = [];
    for (const load of loads) {
      if (!load.result.ok) {
        sourceFailures.push(sourceFailure(load.source.landscape, 'snapshot', load.result.error));
        continue;
      }
      const responseScopeMatches =
        load.result.value.landscape === load.source.landscape &&
        (load.kind === 'health' || load.result.value.tenantId === load.tenant);
      if (!responseScopeMatches) {
        sourceFailures.push(
          sourceFailure(load.source.landscape, 'snapshot', {
            kind: 'unavailable',
            title: 'Landscape response rejected',
            detail: 'The authenticated response did not match its selected landscape or tenant.',
          }),
        );
        continue;
      }
      if (load.kind === 'health') health.push(load.result.value);
      if (load.kind === 'events') retainedEvents.push(...load.result.value.items);
      if (load.kind === 'dead-letters') retainedDeadLetters.push(...load.result.value.items);
    }

    const now = this.#configuration.clock.now();
    const allEvents = retainedEvents.flatMap(item => eventRows(item, now, authorization));
    const allDeadLetters = retainedDeadLetters.map(item => deadLetterValue(item, authorization));
    const events = allEvents.filter(item => matchesFilters(item, filters));
    const deadLetters = allDeadLetters.filter(item => deadLetterMatchesFilters(item, filters));
    const generations = health.map(item => ({
      landscape: redact(item.landscape, authorization),
      desiredGeneration: item.activeGeneration ?? 0,
      activeGeneration: item.activeGeneration ?? 0,
      state: item.activeGeneration === null ? ('failed' as const) : ('current' as const),
      ...(item.compiledAtMs === undefined ? {} : { compiledAt: new Date(item.compiledAtMs) }),
      ...(item.sourceRevision === undefined
        ? {}
        : { detail: `Source revision ${redact(item.sourceRevision, authorization)}` }),
    }));
    const generationByLandscape = new Map(generations.map(item => [item.landscape, item.activeGeneration] as const));
    const hiddenDeliveryLandscapes =
      this.#configuration.previewVisibility.state === 'withheld-d11'
        ? new Set(this.#configuration.previewVisibility.affectedLandscapes)
        : new Set<string>();
    const deliveryEvents = events.filter(item => !hiddenDeliveryLandscapes.has(item.landscape));
    const deliveryDeadLetters = deadLetters.filter(item => !hiddenDeliveryLandscapes.has(item.landscape));
    return {
      ok: true,
      value: {
        generatedAt: now,
        filterOptions: {
          landscapes: optionsFrom(loadedSources.value.map(source => source.landscape)),
          tenants: optionsFrom(tenants.value),
          providers: optionsFrom(allEvents.map(item => item.provider)),
          endpoints: optionsFrom(allEvents.map(item => item.endpointId)),
        },
        intake: health.map(item => ({
          landscape: redact(item.landscape, authorization),
          state: item.status,
          eventsPerMinute: 0,
          verificationFailureRate: 0,
          dedupHitRate: 0,
        })),
        deliveries: deliveryHealth(deliveryEvents, deliveryDeadLetters),
        events,
        deadLetters,
        routes: routeState(events, generationByLandscape),
        generations,
        archives: [],
        quotas: [],
        previewVisibility: copyPreviewVisibility(this.#configuration.previewVisibility),
        sourceFailures,
      },
    };
  }

  async event(
    authorization: ConsoleNativeAuthorization,
    landscape: string,
    eventId: string,
  ): Promise<ConsoleResult<ConsoleEventDetail>> {
    const rejected = authorizationFailure(this.#configuration, authorization, 'operations:read', landscape);
    if (rejected !== undefined) return rejected;
    const tenants = authorizedTenants(authorization.scope);
    if (!tenants.ok) return tenants;
    const source = await selectedSource(this.#gateway, authorization, landscape);
    if (!source.ok) return source;
    const located = await locateEvent(this.#configuration, source.value, authorization, tenants.value, eventId);
    return located.ok
      ? { ok: true, value: eventDetailValue(located.value.detail, this.#configuration, authorization) }
      : located;
  }

  async endpoint(
    authorization: ConsoleNativeAuthorization,
    landscape: string,
    endpointId: string,
  ): Promise<ConsoleResult<ConsoleEndpointReplayTarget>> {
    const rejected = authorizationFailure(this.#configuration, authorization, 'operations:read', landscape);
    if (rejected !== undefined) return rejected;
    const tenants = authorizedTenants(authorization.scope);
    if (!tenants.ok) return tenants;
    const source = await selectedSource(this.#gateway, authorization, landscape);
    if (!source.ok) return source;
    const located = await locateEndpoint(this.#configuration, source.value, authorization, tenants.value, endpointId);
    return located.ok ? { ok: true, value: located.value.target } : located;
  }

  async replayEvent(
    authorization: ConsoleNativeAuthorization,
    input: {
      readonly landscape: string;
      readonly eventId: string;
      readonly endpointId?: string;
      readonly audit: ConsoleActionAudit;
    },
  ): Promise<ConsoleResult<ConsoleActionReceipt>> {
    const rejected = authorizationFailure(this.#configuration, authorization, 'events:replay', input.landscape);
    if (rejected !== undefined) return rejected;
    const tenants = authorizedTenants(authorization.scope);
    if (!tenants.ok) return tenants;
    const source = await selectedSource(this.#gateway, authorization, input.landscape);
    if (!source.ok) return source;
    const located = await locateEvent(this.#configuration, source.value, authorization, tenants.value, input.eventId);
    if (!located.ok) return located;
    if (input.endpointId !== undefined && !located.value.detail.jobs.some(job => job.endpointId === input.endpointId)) {
      return failure(
        'not-found',
        'Delivery obligation not found',
        'The selected endpoint is not a retained obligation for this event.',
      );
    }
    const audited = await auditAction(
      this.#auditor,
      authorization,
      located.value.tenant,
      input.landscape,
      {
        kind: 'event-replay',
        eventId: input.eventId,
        ...(input.endpointId === undefined ? {} : { endpointId: input.endpointId }),
      },
      input.audit,
    );
    if (!audited.ok) return audited;
    const receipt = await sendAction(
      this.#configuration,
      source.value,
      authorization,
      ['tenants', located.value.tenant, 'events', input.eventId, 'replay'],
      {
        ...(input.endpointId === undefined ? {} : { endpointId: input.endpointId }),
        ...auditBody(input.audit),
      },
    );
    return receipt.ok
      ? actionReceiptValue(receipt.value, input.landscape, located.value.tenant, authorization)
      : receipt;
  }

  async replayEndpoint(
    authorization: ConsoleNativeAuthorization,
    input: {
      readonly landscape: string;
      readonly endpointId: string;
      readonly audit: ConsoleActionAudit;
    },
  ): Promise<ConsoleResult<ConsoleActionReceipt>> {
    return this.#endpointAction(authorization, input, 'endpoints:replay', 'replay');
  }

  async reenableEndpoint(
    authorization: ConsoleNativeAuthorization,
    input: {
      readonly landscape: string;
      readonly endpointId: string;
      readonly audit: ConsoleActionAudit;
    },
  ): Promise<ConsoleResult<ConsoleActionReceipt>> {
    return this.#endpointAction(authorization, input, 'endpoints:reenable', 'circuit/re-enable');
  }

  async #endpointAction(
    authorization: ConsoleNativeAuthorization,
    input: {
      readonly landscape: string;
      readonly endpointId: string;
      readonly audit: ConsoleActionAudit;
    },
    capability: 'endpoints:replay' | 'endpoints:reenable',
    actionPath: 'circuit/re-enable' | 'replay',
  ): Promise<ConsoleResult<ConsoleActionReceipt>> {
    const rejected = authorizationFailure(this.#configuration, authorization, capability, input.landscape);
    if (rejected !== undefined) return rejected;
    const tenants = authorizedTenants(authorization.scope);
    if (!tenants.ok) return tenants;
    const source = await selectedSource(this.#gateway, authorization, input.landscape);
    if (!source.ok) return source;
    const located = await locateEndpoint(
      this.#configuration,
      source.value,
      authorization,
      tenants.value,
      input.endpointId,
    );
    if (!located.ok) return located;
    const audited = await auditAction(
      this.#auditor,
      authorization,
      located.value.tenant,
      input.landscape,
      {
        kind: actionPath === 'replay' ? 'endpoint-replay' : 'circuit-reenable',
        endpointId: input.endpointId,
      },
      input.audit,
    );
    if (!audited.ok) return audited;
    const actionSegments =
      actionPath === 'replay'
        ? ['tenants', located.value.tenant, 'endpoints', input.endpointId, 'replay']
        : ['tenants', located.value.tenant, 'endpoints', input.endpointId, 'circuit', 're-enable'];
    const receipt = await sendAction(
      this.#configuration,
      source.value,
      authorization,
      actionSegments,
      auditBody(input.audit),
    );
    return receipt.ok
      ? actionReceiptValue(receipt.value, input.landscape, located.value.tenant, authorization)
      : receipt;
  }
}
