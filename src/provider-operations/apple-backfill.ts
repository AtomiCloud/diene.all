import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type { Clock, IdentifierFactory, IntakeFailure, IntakeOutcome, IntakeRequest } from '../domain/index.ts';

export interface AppleHistoryFailure {
  readonly code: string;
  readonly message: string;
  readonly retryable: boolean;
}

interface AppleHistoryNotification {
  readonly signedPayload: string;
}

export interface AppleHistoryPage {
  readonly notifications: readonly AppleHistoryNotification[];
  readonly hasMore: boolean;
  /** Opaque page-level token returned by Apple's notification history API. */
  readonly cursorAfter: string;
}

export interface AppleNotificationHistoryClient {
  listNotifications(input: {
    readonly cursor?: string;
    /** Must accommodate Apple's fixed maximum page size of 20. */
    readonly limit: number;
    readonly signal: AbortSignal;
  }): Promise<Result<AppleHistoryPage, AppleHistoryFailure>>;
}

export interface AppleBackfillStoreFailure {
  readonly code: 'unavailable' | 'invalid-state';
  readonly message: string;
  readonly retryable: boolean;
}

export interface AppleBackfillLease {
  readonly operationKey: string;
  readonly ownerId: string;
  readonly token: string;
  readonly expiresAtMs: number;
}

export interface AppleBackfillState {
  readonly cursor?: string;
  readonly consecutiveMissedCycles: number;
  readonly alert: boolean;
}

export interface AppleBackfillStateStore {
  acquireLease(input: {
    readonly operationKey: string;
    readonly ownerId: string;
    readonly token: string;
    readonly nowMs: number;
    readonly leaseDurationMs: number;
  }): Promise<Result<AppleBackfillLease | null, AppleBackfillStoreFailure>>;

  renewLease(input: {
    readonly lease: AppleBackfillLease;
    readonly nowMs: number;
    readonly leaseDurationMs: number;
  }): Promise<Result<AppleBackfillLease | null, AppleBackfillStoreFailure>>;

  releaseLease(lease: AppleBackfillLease): Promise<Result<boolean, AppleBackfillStoreFailure>>;

  readState(operationKey: string): Promise<Result<AppleBackfillState, AppleBackfillStoreFailure>>;

  advanceCursor(input: {
    readonly lease: AppleBackfillLease;
    readonly expectedCursor?: string;
    readonly cursorAfter: string;
    readonly nowMs: number;
  }): Promise<Result<AppleBackfillState | null, AppleBackfillStoreFailure>>;

  recordCycleSuccess(input: {
    readonly lease: AppleBackfillLease;
    readonly nowMs: number;
  }): Promise<Result<AppleBackfillState | null, AppleBackfillStoreFailure>>;

  recordMissedCycle(input: {
    readonly lease: AppleBackfillLease;
    readonly nowMs: number;
  }): Promise<Result<AppleBackfillState | null, AppleBackfillStoreFailure>>;
}

export interface AppleBackfillIntake {
  intake(request: IntakeRequest): Promise<Result<IntakeOutcome, IntakeFailure>>;
  /**
   * Marks the durably persisted event acknowledged so its delivery jobs enter
   * the ready queue — the same acknowledgement the HTTP provider path performs
   * before returning 200. Backfill reuses it so persisted history events are
   * actually deliverable rather than durably stranded.
   */
  acknowledge(eventId: string): Promise<Result<void, IntakeFailure>>;
}

export interface AppleBackfillOptions {
  readonly operationKey: string;
  readonly landscape: string;
  readonly preferredHostLandscape: string;
  readonly intakePath: string;
  readonly leaseDurationMs: number;
  readonly pageSize?: number;
}

type AppleBackfillCycleStatus = 'completed' | 'cancelled' | 'excluded' | 'not-preferred-host';

export interface AppleBackfillCycleReport {
  readonly status: AppleBackfillCycleStatus;
  readonly processedNotifications: number;
  readonly state?: AppleBackfillState;
}

export interface AppleBackfillCycleFailure {
  readonly code: 'history-failed' | 'intake-failed' | 'invalid-history' | 'lease-lost' | 'state-store-failed';
  readonly message: string;
  readonly retryable: boolean;
  readonly processedNotifications: number;
  readonly state?: AppleBackfillState;
}

const DEFAULT_PAGE_SIZE = 100;

const validPositiveInteger = (value: number): boolean => Number.isSafeInteger(value) && value > 0;

const stateStoreFailure = (
  failure: AppleBackfillStoreFailure,
  processedNotifications: number,
  state?: AppleBackfillState,
): AppleBackfillCycleFailure => ({
  code: 'state-store-failed',
  message: `Apple backfill state store failed (${failure.code})`,
  retryable: failure.retryable,
  processedNotifications,
  ...(state === undefined ? {} : { state }),
});

const leaseLost = (processedNotifications: number, state?: AppleBackfillState): AppleBackfillCycleFailure => ({
  code: 'lease-lost',
  message: 'Apple backfill singleton lease was lost',
  retryable: true,
  processedNotifications,
  ...(state === undefined ? {} : { state }),
});

/**
 * Runs one bounded Apple notification-history cycle.
 *
 * The runner never verifies or persists events itself. It reconstructs Apple's
 * ordinary signed-notification request body and passes it through the injected
 * intake engine, preserving the normal verification, deduplication, fan-out,
 * and persistence boundary.
 */
export class AppleServerApiBackfillRunner {
  readonly pageSize: number;

  constructor(
    readonly history: AppleNotificationHistoryClient,
    readonly stateStore: AppleBackfillStateStore,
    readonly intakeEngine: AppleBackfillIntake,
    readonly clock: Clock,
    readonly identifiers: IdentifierFactory,
    readonly options: AppleBackfillOptions,
  ) {
    this.pageSize = options.pageSize ?? DEFAULT_PAGE_SIZE;
    if (
      options.operationKey.length === 0 ||
      options.landscape.length === 0 ||
      options.preferredHostLandscape.length === 0 ||
      options.intakePath.length === 0
    ) {
      throw new TypeError('Apple backfill identifiers and intake path are required');
    }
    if (!validPositiveInteger(options.leaseDurationMs) || !validPositiveInteger(this.pageSize)) {
      throw new RangeError('Apple backfill lease duration and page size must be positive integers');
    }
  }

  async runCycle(signal: AbortSignal): Promise<Result<AppleBackfillCycleReport, AppleBackfillCycleFailure>> {
    if (this.options.landscape !== this.options.preferredHostLandscape) {
      return Ok({
        status: 'not-preferred-host',
        processedNotifications: 0,
      });
    }
    if (signal.aborted) {
      return Ok({ status: 'cancelled', processedNotifications: 0 });
    }

    const acquired = await this.stateStore.acquireLease({
      operationKey: this.options.operationKey,
      ownerId: this.options.landscape,
      token: this.identifiers.create(),
      nowMs: this.clock.nowMs(),
      leaseDurationMs: this.options.leaseDurationMs,
    });
    if (await acquired.isErr()) {
      return Err(stateStoreFailure(await acquired.unwrapErr(), 0));
    }
    const initialLease = await acquired.unwrap();
    if (initialLease === null) {
      return Ok({ status: 'excluded', processedNotifications: 0 });
    }

    let result: Result<AppleBackfillCycleReport, AppleBackfillCycleFailure>;
    try {
      result = await this.runWithLease(initialLease, signal);
    } catch {
      result = Err({
        code: 'state-store-failed',
        message: 'Apple backfill dependency failed unexpectedly',
        retryable: true,
        processedNotifications: 0,
      });
    }

    const released = await this.stateStore.releaseLease(initialLease);
    if ((await released.isErr()) && (await result.isOk())) {
      const report = await result.unwrap();
      return Err(stateStoreFailure(await released.unwrapErr(), report.processedNotifications, report.state));
    }
    return result;
  }

  private async runWithLease(
    initialLease: AppleBackfillLease,
    signal: AbortSignal,
  ): Promise<Result<AppleBackfillCycleReport, AppleBackfillCycleFailure>> {
    let lease = initialLease;
    let processedNotifications = 0;
    const initialState = await this.stateStore.readState(this.options.operationKey);
    if (await initialState.isErr()) {
      return Err(stateStoreFailure(await initialState.unwrapErr(), 0));
    }
    let state = await initialState.unwrap();
    let cursor = state.cursor;

    while (true) {
      if (signal.aborted) {
        state = await this.recordMissedCycle(lease, state);
        return Ok({
          status: 'cancelled',
          processedNotifications,
          state,
        });
      }

      const renewed = await this.renewLease(lease);
      if (await renewed.isErr()) {
        return Err(stateStoreFailure(await renewed.unwrapErr(), processedNotifications, state));
      }
      const renewedLease = await renewed.unwrap();
      if (renewedLease === null) {
        return Err(leaseLost(processedNotifications, state));
      }
      lease = renewedLease;

      const pageResult = await this.history.listNotifications({
        ...(cursor === undefined ? {} : { cursor }),
        limit: this.pageSize,
        signal,
      });
      if (await pageResult.isErr()) {
        const failure = await pageResult.unwrapErr();
        state = await this.recordMissedCycle(lease, state);
        return Err({
          code: 'history-failed',
          message: `Apple notification history failed (${failure.code})`,
          retryable: failure.retryable,
          processedNotifications,
          state,
        });
      }
      const page = await pageResult.unwrap();
      if (
        page.cursorAfter.length === 0 ||
        (page.hasMore && (page.notifications.length === 0 || page.cursorAfter === cursor))
      ) {
        state = await this.recordMissedCycle(lease, state);
        return Err({
          code: 'invalid-history',
          message: 'Apple notification history returned an invalid page cursor',
          retryable: true,
          processedNotifications,
          state,
        });
      }

      for (const notification of page.notifications) {
        if (signal.aborted) {
          state = await this.recordMissedCycle(lease, state);
          return Ok({
            status: 'cancelled',
            processedNotifications,
            state,
          });
        }
        const itemLeaseResult = await this.renewLease(lease);
        if (await itemLeaseResult.isErr()) {
          return Err(stateStoreFailure(await itemLeaseResult.unwrapErr(), processedNotifications, state));
        }
        const itemLease = await itemLeaseResult.unwrap();
        if (itemLease === null) {
          return Err(leaseLost(processedNotifications, state));
        }
        lease = itemLease;

        const intakeResult = await this.intakeEngine.intake(this.intakeRequest(notification.signedPayload));
        if (await intakeResult.isErr()) {
          const failure = await intakeResult.unwrapErr();
          state = await this.recordMissedCycle(lease, state);
          return Err({
            code: 'intake-failed',
            message: `Apple backfill intake failed (${failure.code})`,
            retryable: failure.code !== 'verification-failed',
            processedNotifications,
            state,
          });
        }

        // Persistence alone does not make an event deliverable: only
        // acknowledgement inserts its jobs into the ready queue. Acknowledge the
        // original event id for both accepted and duplicate outcomes before the
        // item is counted or the page cursor advances, so a persisted backfill
        // event is never durably stranded. An acknowledgement failure is
        // retryable and must retain the cursor for the next cycle.
        const outcome = await intakeResult.unwrap();
        const acknowledged = await this.intakeEngine.acknowledge(outcome.eventId);
        if (await acknowledged.isErr()) {
          const failure = await acknowledged.unwrapErr();
          state = await this.recordMissedCycle(lease, state);
          return Err({
            code: 'intake-failed',
            message: `Apple backfill acknowledgement failed (${failure.code})`,
            retryable: true,
            processedNotifications,
            state,
          });
        }

        // Cancellation here intentionally retains the cursor. The durable
        // intake result will be replayed as a duplicate on the next cycle.
        if (signal.aborted) {
          state = await this.recordMissedCycle(lease, state);
          return Ok({
            status: 'cancelled',
            processedNotifications,
            state,
          });
        }
        processedNotifications += 1;
      }

      // Apple's pagination token covers the whole page. Checkpoint only
      // after every notification in that page has reached durable intake.
      // A partial failure therefore replays the page and relies on ordinary
      // intake deduplication for the already accepted notifications.
      if (signal.aborted) {
        state = await this.recordMissedCycle(lease, state);
        return Ok({
          status: 'cancelled',
          processedNotifications,
          state,
        });
      }
      const advanced = await this.stateStore.advanceCursor({
        lease,
        ...(cursor === undefined ? {} : { expectedCursor: cursor }),
        cursorAfter: page.cursorAfter,
        nowMs: this.clock.nowMs(),
      });
      if (await advanced.isErr()) {
        return Err(stateStoreFailure(await advanced.unwrapErr(), processedNotifications, state));
      }
      const advancedState = await advanced.unwrap();
      if (advancedState === null) {
        return Err(leaseLost(processedNotifications, state));
      }
      state = advancedState;
      cursor = page.cursorAfter;

      if (!page.hasMore) {
        const succeeded = await this.stateStore.recordCycleSuccess({
          lease,
          nowMs: this.clock.nowMs(),
        });
        if (await succeeded.isErr()) {
          return Err(stateStoreFailure(await succeeded.unwrapErr(), processedNotifications, state));
        }
        const successState = await succeeded.unwrap();
        if (successState === null) {
          return Err(leaseLost(processedNotifications, state));
        }
        return Ok({
          status: 'completed',
          processedNotifications,
          state: successState,
        });
      }
    }
  }

  private renewLease(lease: AppleBackfillLease): Promise<Result<AppleBackfillLease | null, AppleBackfillStoreFailure>> {
    return this.stateStore.renewLease({
      lease,
      nowMs: this.clock.nowMs(),
      leaseDurationMs: this.options.leaseDurationMs,
    });
  }

  private async recordMissedCycle(
    lease: AppleBackfillLease,
    fallback: AppleBackfillState,
  ): Promise<AppleBackfillState> {
    const missed = await this.stateStore.recordMissedCycle({
      lease,
      nowMs: this.clock.nowMs(),
    });
    if (await missed.isErr()) {
      return fallback;
    }
    return (await missed.unwrap()) ?? fallback;
  }

  private intakeRequest(signedPayload: string): IntakeRequest {
    return {
      path: this.options.intakePath,
      headers: { 'content-type': 'application/json' },
      rawBody: new TextEncoder().encode(JSON.stringify({ signedPayload })),
    };
  }
}
