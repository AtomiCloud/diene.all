import type { Problem } from '@atomicloud/diene.problems';
import { Err, Ok, type Result, type ResultSerial } from '@atomicloud/diene.result';
import type {
  BackendPhase,
  CreateUserRequest,
  OnboardingApiResponse,
  OnboardingBackendApi,
  OnboardSync,
  OnboardSyncState,
} from '../lib/onboard/sync';

type ApiStep = number | Problem;

function responseForStep(step: ApiStep): Result<OnboardingApiResponse, Problem> {
  return typeof step === 'number' ? Ok({ status: step }) : Err(step);
}

export class FakeOnboardingBackendApi implements OnboardingBackendApi {
  readonly getMeCalls: string[] = [];
  readonly createUserCalls: CreateUserRequest[] = [];
  readonly #getMeScript: ApiStep[];
  readonly #createScript: ApiStep[];

  constructor(options: { readonly getMe?: readonly ApiStep[]; readonly create?: readonly ApiStep[] } = {}) {
    this.#getMeScript = [...(options.getMe ?? [200])];
    this.#createScript = [...(options.create ?? [201])];
  }

  getMe(accessToken: string): Result<OnboardingApiResponse, Problem> {
    this.getMeCalls.push(accessToken);
    return responseForStep(this.#getMeScript.shift() ?? 500);
  }

  createUser(request: CreateUserRequest): Result<OnboardingApiResponse, Problem> {
    this.createUserCalls.push(request);
    return responseForStep(this.#createScript.shift() ?? 500);
  }
}

export class InMemoryOnboardSyncState implements OnboardSyncState {
  readonly phaseValues = new Map<string, BackendPhase>();
  readonly flightValues = new Map<string, Promise<ResultSerial<BackendPhase, Problem>>>();

  getPhase(backendId: string): BackendPhase | undefined {
    return this.phaseValues.get(backendId);
  }

  setPhase(backendId: string, phase: BackendPhase): void {
    this.phaseValues.set(backendId, phase);
  }

  getFlight(backendId: string): Promise<ResultSerial<BackendPhase, Problem>> | undefined {
    return this.flightValues.get(backendId);
  }

  setFlight(backendId: string, flight: Promise<ResultSerial<BackendPhase, Problem>>): void {
    this.flightValues.set(backendId, flight);
  }

  deleteFlight(backendId: string, flight: Promise<ResultSerial<BackendPhase, Problem>>): void {
    if (this.flightValues.get(backendId) === flight) this.flightValues.delete(backendId);
  }
}

export class PhaseAssertionError extends Error {
  constructor(
    readonly expected: BackendPhase['kind'],
    readonly actual: BackendPhase['kind'] | undefined,
  ) {
    super(`Expected onboarding phase ${expected}, received ${actual ?? 'undefined'}`);
    this.name = 'PhaseAssertionError';
  }
}

export function expectPhase(actual: BackendPhase | undefined, expected: BackendPhase['kind']): BackendPhase {
  if (actual?.kind !== expected) throw new PhaseAssertionError(expected, actual?.kind);
  return actual;
}

export async function driveBackendPhase(
  sync: OnboardSync,
  backendId: string,
  expected: BackendPhase['kind'],
): Promise<BackendPhase> {
  await sync.syncBackend(backendId).native();
  return expectPhase(await sync.phase(backendId).unwrap(), expected);
}
