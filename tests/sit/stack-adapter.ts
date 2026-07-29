import {
  type MercuryTestStack,
  type MercuryTestStackFactory,
  type ProviderName,
  requiredProviderNames,
} from './contract.ts';

const requiredEnvironment = ['MERCURY_SIT_BASE_URL', 'MERCURY_SIT_CONTROL_URL'] as const;

const requiredMethods = [
  'close',
  'inspectDependencies',
  'runProviderVerificationMatrix',
  'runAtomicAcceptance',
  'runFanout',
  'runSignatureLifecycle',
  'runConsoleJourney',
  'runAppleBackfill',
  'inspectGoogleSubscription',
  'runArchiveLifecycle',
  'inspectRoute53Landing',
] as const satisfies readonly (keyof MercuryTestStack)[];

const assertEnvironment = (): void => {
  const missing = requiredEnvironment.filter(name => {
    const value = process.env[name];
    return value === undefined || value.trim().length === 0;
  });

  if (missing.length > 0) {
    throw new Error(`Mercury SIT requires an injected real stack; missing environment: ${missing.join(', ')}`);
  }
};

const assertStack: (candidate: unknown) => asserts candidate is MercuryTestStack = candidate => {
  if (candidate === null || typeof candidate !== 'object') {
    throw new Error('createMercuryTestStack returned no stack object');
  }

  for (const method of requiredMethods) {
    if (typeof Reflect.get(candidate, method) !== 'function') {
      throw new Error(`createMercuryTestStack is missing required method: ${method}`);
    }
  }
};

const loadMercuryTestStackFactory = async (): Promise<MercuryTestStackFactory> => {
  // Keep the public export expectation isolated here while sibling source
  // scopes compose src/index.ts. SIT cases import only this structural adapter.
  const sourceModule = (await import('../../src/index.ts')) as unknown as {
    readonly createMercuryTestStack?: MercuryTestStackFactory;
  };
  const factory = sourceModule.createMercuryTestStack;
  if (typeof factory !== 'function') {
    throw new Error(
      'Mercury SIT requires the public src/index.ts export createMercuryTestStack; no fallback or skipped tests are allowed',
    );
  }

  return factory;
};

export const createMercuryTestStackFromEnvironment = async (
  environment: Readonly<Record<string, string | undefined>>,
  requiredProviderFixtures: readonly ProviderName[] = requiredProviderNames,
): Promise<MercuryTestStack> => {
  const factory = await loadMercuryTestStackFactory();

  const stack = await factory({
    environment,
    requiredProviderFixtures,
  });
  assertStack(stack);
  return stack;
};

export const loadMercuryTestStack = async (): Promise<MercuryTestStack> => {
  assertEnvironment();
  return createMercuryTestStackFromEnvironment(process.env);
};
