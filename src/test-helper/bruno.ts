export interface BrunoEnvironmentOptions {
  readonly baseUrl: string;
  readonly accessToken?: string;
  readonly variables?: Readonly<Record<string, string>>;
}

const BRUNO_VARIABLE = /^[A-Za-z_][A-Za-z0-9_]*$/;

/** Create the string-only environment map consumed by a Bruno API collection. */
export function createBrunoEnvironment(options: BrunoEnvironmentOptions): Readonly<Record<string, string>> {
  let baseUrl: URL;
  try {
    baseUrl = new URL(options.baseUrl);
  } catch {
    throw new TypeError('baseUrl must be an absolute HTTP(S) URL');
  }
  if (!['http:', 'https:'].includes(baseUrl.protocol) || baseUrl.username !== '' || baseUrl.password !== '') {
    throw new TypeError('baseUrl must be an absolute HTTP(S) URL without credentials');
  }

  const environment: Record<string, string> = { ...(options.variables ?? {}) };
  for (const [key, value] of Object.entries(environment)) {
    if (!BRUNO_VARIABLE.test(key) || typeof value !== 'string') {
      throw new TypeError('Bruno variables must use identifier keys and string values');
    }
  }
  environment.baseUrl = baseUrl.toString().replace(/\/$/, '');
  if (options.accessToken !== undefined) {
    if (typeof options.accessToken !== 'string') {
      throw new TypeError('accessToken must be a string');
    }
    environment.accessToken = options.accessToken;
  }
  return Object.freeze(environment);
}
