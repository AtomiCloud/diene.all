import { type CanonicalResourceKey, canonicalResourceKey } from '@atomicloud/diene.auth-engine';
import type { Problem } from '@atomicloud/diene.problems';
import { Err, Ok, Res, type Result, type ResultSerial } from '@atomicloud/diene.result';

import { createBackendFetch } from './backend-fetch';
import { validateBaseUrl, validateCoordinate } from './lpsm';
import { createBackendNotFoundProblem, createConfigurationProblem } from './problems';
import { proxyApiClient } from './proxy';
import type {
  ApiClient,
  ApiEngine,
  ApiEngineOptions,
  BackendBinding,
  FetchLike,
  LpsmCoordinate,
  LpsmKey,
  ResolvedBackend,
} from './types';

const DEFAULT_TIMEOUT_MS = 15_000;

interface ReadyBinding {
  readonly binding: BackendBinding;
  readonly coordinate: LpsmCoordinate;
  readonly key: LpsmKey;
  readonly baseUrl: string;
  readonly resourceKey: CanonicalResourceKey;
  readonly timeoutMs: number;
}

function validTimeout(value: number | undefined): number | undefined {
  const timeout = value ?? DEFAULT_TIMEOUT_MS;
  return Number.isFinite(timeout) && timeout > 0 ? timeout : undefined;
}

function globalFetch(): FetchLike {
  return globalThis.fetch.bind(globalThis) as FetchLike;
}

async function prepare(options: ApiEngineOptions): Promise<ResultSerial<readonly ReadyBinding[], Problem>> {
  const entries: ReadyBinding[] = [];
  const keys = new Set<LpsmKey>();

  for (const binding of options.bindings) {
    const coordinate = validateCoordinate(binding.coordinate);
    const label = coordinate.ok ? coordinate.key : 'invalid/coordinate';
    if (!coordinate.ok) {
      return ['err', createConfigurationProblem(options.problems, label, coordinate.reason)];
    }
    if (keys.has(coordinate.key)) {
      return [
        'err',
        createConfigurationProblem(
          options.problems,
          coordinate.key,
          `Duplicate backend registration for ${coordinate.key}.`,
        ),
      ];
    }

    const url = validateBaseUrl(binding.baseUrl);
    if (!url.ok) {
      return ['err', createConfigurationProblem(options.problems, coordinate.key, url.reason)];
    }
    const timeoutMs = validTimeout(binding.timeoutMs);
    if (timeoutMs === undefined) {
      return [
        'err',
        createConfigurationProblem(
          options.problems,
          coordinate.key,
          'Backend timeoutMs must be a finite positive number.',
        ),
      ];
    }

    let resource: ResultSerial<CanonicalResourceKey, Problem>;
    try {
      resource = await canonicalResourceKey(binding.resource).serial();
    } catch (error) {
      return [
        'err',
        createConfigurationProblem(
          options.problems,
          coordinate.key,
          error instanceof Error ? error.message : 'Backend resource could not be canonicalized.',
        ),
      ];
    }
    if (resource[0] === 'err') return resource;

    keys.add(coordinate.key);
    entries.push(
      Object.freeze({
        binding,
        coordinate: coordinate.coordinate,
        key: coordinate.key,
        baseUrl: url.baseUrl,
        resourceKey: resource[1],
        timeoutMs,
      }),
    );
  }
  return ['ok', Object.freeze(entries)];
}

class ImmutableApiEngine implements ApiEngine {
  readonly #entries: ReadonlyMap<LpsmKey, ReadyBinding>;
  readonly #fetch: FetchLike;
  readonly #options: ApiEngineOptions;

  constructor(entries: readonly ReadyBinding[], options: ApiEngineOptions) {
    this.#entries = new Map(entries.map(entry => [entry.key, entry]));
    this.#fetch = options.fetch ?? globalFetch();
    this.#options = options;
  }

  resolve<TClient extends object>(coordinateInput: LpsmCoordinate): Result<ApiClient<TClient>, Problem> {
    const coordinate = validateCoordinate(coordinateInput);
    if (!coordinate.ok) {
      return Err(createConfigurationProblem(this.#options.problems, 'invalid/coordinate', coordinate.reason));
    }
    const entry = this.#entries.get(coordinate.key);
    if (entry === undefined) {
      return Err(createBackendNotFoundProblem(this.#options.problems, coordinate.key));
    }

    try {
      const client = entry.binding.createClient({
        baseUrl: entry.baseUrl,
        fetch: createBackendFetch({
          backend: entry.coordinate,
          backendKey: entry.key,
          baseUrl: entry.baseUrl,
          resourceKey: entry.resourceKey,
          auth: entry.binding.auth,
          problems: this.#options.problems,
          fetch: this.#fetch,
          timeoutMs: entry.timeoutMs,
          ...(entry.binding.rescue === undefined ? {} : { rescue: entry.binding.rescue }),
        }),
      });
      if (typeof client !== 'object' || client === null || 'then' in client) {
        return Err(
          createConfigurationProblem(
            this.#options.problems,
            entry.key,
            'Backend createClient must synchronously return a Kiota-shaped object.',
          ),
        );
      }
      return Ok(
        proxyApiClient(client as TClient, {
          backend: entry.coordinate,
          backendKey: entry.key,
          problems: this.#options.problems,
        }),
      );
    } catch (error) {
      return Err(
        createConfigurationProblem(
          this.#options.problems,
          entry.key,
          error instanceof Error ? error.message : 'Backend client construction failed.',
        ),
      );
    }
  }

  list(): readonly ResolvedBackend[] {
    return Object.freeze(
      [...this.#entries.values()].map(entry =>
        Object.freeze({
          coordinate: entry.coordinate,
          key: entry.key,
          baseUrl: entry.baseUrl,
          resourceKey: entry.resourceKey,
        }),
      ),
    );
  }
}

/** Build a ready immutable engine from the application's single backend registration list. */
export function createApiEngine(options: ApiEngineOptions): Result<ApiEngine, Problem> {
  return Res.fromSerial<ApiEngine, Problem>(
    prepare(options)
      .then(
        (serial): ResultSerial<ApiEngine, Problem> =>
          serial[0] === 'err' ? serial : ['ok', new ImmutableApiEngine(serial[1], options)],
      )
      .catch(
        (error): ResultSerial<ApiEngine, Problem> => [
          'err',
          createConfigurationProblem(
            options.problems,
            'api-engine',
            error instanceof Error ? error.message : 'API engine construction failed.',
          ),
        ],
      ),
  );
}
