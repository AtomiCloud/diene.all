import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type {
  Clock,
  ConfigSnapshotSource,
  IdentifierFactory,
  ProviderVerifierRegistry,
  RegistrationSnapshot,
  RuntimeTelemetry,
  SecretReader,
  SecretReadFailure,
  StorageFailure,
  TelemetryEvent,
  VerificationEvidence,
  VerificationFailure,
  VerificationInput,
} from '../domain/index.ts';

export class ManualClock implements Clock {
  constructor(public currentMs: number) {}

  nowMs(): number {
    return this.currentMs;
  }

  advance(milliseconds: number): void {
    this.currentMs += milliseconds;
  }
}

export class SequenceIdentifierFactory implements IdentifierFactory {
  readonly values: string[];

  constructor(values: readonly string[]) {
    this.values = [...values];
  }

  create(): string {
    return this.values.shift() ?? `generated-${this.values.length}`;
  }
}

export type VerificationHandler = (
  input: VerificationInput,
) => Promise<Result<VerificationEvidence, VerificationFailure>>;

export class ProviderVerifierMap implements ProviderVerifierRegistry {
  readonly handlers: ReadonlyMap<string, VerificationHandler>;

  constructor(handlers: Readonly<Record<string, VerificationHandler>>) {
    this.handlers = new Map(Object.entries(handlers));
  }

  async verify(input: VerificationInput): Promise<Result<VerificationEvidence, VerificationFailure>> {
    const handler = this.handlers.get(input.provider);
    if (handler === undefined) {
      return Err({
        code: 'unsupported-provider',
        message: `no verifier registered for ${input.provider}`,
      });
    }
    return handler(input);
  }
}

export class MemorySnapshotSource implements ConfigSnapshotSource {
  public snapshot: RegistrationSnapshot;
  public failure: StorageFailure | null = null;
  public reads = 0;

  constructor(snapshot: RegistrationSnapshot) {
    this.snapshot = snapshot;
  }

  async read(): Promise<Result<RegistrationSnapshot, StorageFailure>> {
    this.reads += 1;
    return this.failure === null ? Ok(this.snapshot) : Err(this.failure);
  }
}

export class MemorySecretReader implements SecretReader {
  readonly secrets: Map<string, Uint8Array>;

  constructor(secrets: Readonly<Record<string, Uint8Array>>) {
    this.secrets = new Map(Object.entries(secrets).map(([key, value]) => [key, value.slice()]));
  }

  async read(secretRef: string): Promise<Result<Uint8Array, SecretReadFailure>> {
    const secret = this.secrets.get(secretRef);
    return secret === undefined
      ? Err({ code: 'not-found', message: `secret not found: ${secretRef}` })
      : Ok(secret.slice());
  }
}

export class MemoryTelemetry implements RuntimeTelemetry {
  readonly events: TelemetryEvent[] = [];

  async record(event: TelemetryEvent): Promise<void> {
    this.events.push(event);
  }
}
