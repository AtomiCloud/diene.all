import { describe, expect, test } from 'bun:test';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type { IntakeFailure, IntakeOutcome, IntakeRequest } from '../../../src/domain/index.ts';
import {
  type AppleBackfillLease,
  type AppleBackfillState,
  type AppleBackfillStateStore,
  type AppleBackfillStoreFailure,
  type AppleHistoryFailure,
  type AppleHistoryPage,
  type AppleNotificationHistoryClient,
  AppleServerApiBackfillRunner,
} from '../../../src/provider-operations/apple-backfill.ts';

const storeFailure: AppleBackfillStoreFailure = {
  code: 'unavailable',
  message: 'store failed',
  retryable: true,
};

class FakeAppleStateStore implements AppleBackfillStateStore {
  state: AppleBackfillState = {
    consecutiveMissedCycles: 0,
    alert: false,
  };
  acquireEnabled = true;
  loseLeaseOnRenewal = Number.POSITIVE_INFINITY;
  renewals = 0;
  acquisitions = 0;
  releases = 0;
  advances: string[] = [];
  activeLease: AppleBackfillLease | undefined;

  async acquireLease(input: {
    readonly operationKey: string;
    readonly ownerId: string;
    readonly token: string;
    readonly nowMs: number;
    readonly leaseDurationMs: number;
  }): Promise<Result<AppleBackfillLease | null, AppleBackfillStoreFailure>> {
    this.acquisitions += 1;
    if (!this.acquireEnabled || this.activeLease !== undefined) {
      return Ok(null);
    }
    this.activeLease = {
      operationKey: input.operationKey,
      ownerId: input.ownerId,
      token: input.token,
      expiresAtMs: input.nowMs + input.leaseDurationMs,
    };
    return Ok(this.activeLease);
  }

  async renewLease(input: {
    readonly lease: AppleBackfillLease;
    readonly nowMs: number;
    readonly leaseDurationMs: number;
  }): Promise<Result<AppleBackfillLease | null, AppleBackfillStoreFailure>> {
    this.renewals += 1;
    if (this.renewals >= this.loseLeaseOnRenewal || this.activeLease?.token !== input.lease.token) {
      this.activeLease = undefined;
      return Ok(null);
    }
    this.activeLease = {
      ...input.lease,
      expiresAtMs: input.nowMs + input.leaseDurationMs,
    };
    return Ok(this.activeLease);
  }

  async releaseLease(lease: AppleBackfillLease): Promise<Result<boolean, AppleBackfillStoreFailure>> {
    this.releases += 1;
    if (this.activeLease?.token !== lease.token) {
      return Ok(false);
    }
    this.activeLease = undefined;
    return Ok(true);
  }

  async readState(): Promise<Result<AppleBackfillState, AppleBackfillStoreFailure>> {
    return Ok(this.state);
  }

  async advanceCursor(input: {
    readonly lease: AppleBackfillLease;
    readonly expectedCursor?: string;
    readonly cursorAfter: string;
    readonly nowMs: number;
  }): Promise<Result<AppleBackfillState | null, AppleBackfillStoreFailure>> {
    if (this.activeLease?.token !== input.lease.token || this.state.cursor !== input.expectedCursor) {
      return Ok(null);
    }
    this.advances.push(input.cursorAfter);
    this.state = { ...this.state, cursor: input.cursorAfter };
    return Ok(this.state);
  }

  async recordCycleSuccess(input: {
    readonly lease: AppleBackfillLease;
    readonly nowMs: number;
  }): Promise<Result<AppleBackfillState | null, AppleBackfillStoreFailure>> {
    if (this.activeLease?.token !== input.lease.token) {
      return Ok(null);
    }
    this.state = {
      ...(this.state.cursor === undefined ? {} : { cursor: this.state.cursor }),
      consecutiveMissedCycles: 0,
      alert: false,
    };
    return Ok(this.state);
  }

  async recordMissedCycle(input: {
    readonly lease: AppleBackfillLease;
    readonly nowMs: number;
  }): Promise<Result<AppleBackfillState | null, AppleBackfillStoreFailure>> {
    if (this.activeLease?.token !== input.lease.token) {
      return Ok(null);
    }
    const consecutiveMissedCycles = this.state.consecutiveMissedCycles + 1;
    this.state = {
      ...(this.state.cursor === undefined ? {} : { cursor: this.state.cursor }),
      consecutiveMissedCycles,
      alert: consecutiveMissedCycles > 2,
    };
    return Ok(this.state);
  }
}

class FakeHistory implements AppleNotificationHistoryClient {
  readonly cursors: Array<string | undefined> = [];

  constructor(readonly handler: (cursor: string | undefined) => Result<AppleHistoryPage, AppleHistoryFailure>) {}

  async listNotifications(input: {
    readonly cursor?: string;
    readonly limit: number;
    readonly signal: AbortSignal;
  }): Promise<Result<AppleHistoryPage, AppleHistoryFailure>> {
    this.cursors.push(input.cursor);
    return this.handler(input.cursor);
  }
}

class FakeIntake {
  readonly requests: IntakeRequest[] = [];
  readonly acknowledged: string[] = [];

  constructor(
    readonly outcomes: Array<Result<IntakeOutcome, IntakeFailure>>,
    readonly onIntake?: () => void,
    readonly acknowledgeOutcomes: Array<Result<void, IntakeFailure>> = [],
  ) {}

  async intake(request: IntakeRequest): Promise<Result<IntakeOutcome, IntakeFailure>> {
    this.requests.push(request);
    this.onIntake?.();
    return (
      this.outcomes.shift() ??
      Err({
        code: 'persistence-unavailable',
        message: 'unexpected intake',
      })
    );
  }

  async acknowledge(eventId: string): Promise<Result<void, IntakeFailure>> {
    this.acknowledged.push(eventId);
    return this.acknowledgeOutcomes.shift() ?? Ok(undefined);
  }
}

const options = {
  operationKey: 'apple-history:tenant-a',
  landscape: 'mew',
  preferredHostLandscape: 'mew',
  intakePath: '/t/tenant-a/webhook/apple',
  leaseDurationMs: 60_000,
};

const runner = (
  history: AppleNotificationHistoryClient,
  store: FakeAppleStateStore,
  intake: FakeIntake,
  overrides: Partial<typeof options> = {},
): AppleServerApiBackfillRunner =>
  new AppleServerApiBackfillRunner(
    history,
    store,
    intake,
    { nowMs: () => 1_785_283_200_000 },
    { create: () => 'lease-token' },
    { ...options, ...overrides },
  );

describe('Apple Server API backfill', () => {
  test('does no work outside the management-DB preferred-host landscape', async () => {
    const store = new FakeAppleStateStore();
    const history = new FakeHistory(() => Ok({ notifications: [], hasMore: false, cursorAfter: 'terminal' }));
    const result = await runner(history, store, new FakeIntake([]), {
      landscape: 'raichu',
    }).runCycle(new AbortController().signal);

    expect(await result.unwrap()).toEqual({
      status: 'not-preferred-host',
      processedNotifications: 0,
    });
    expect(store.acquisitions).toBe(0);
    expect(history.cursors).toHaveLength(0);
  });

  test('excludes a second singleton and reports lease loss', async () => {
    const excludedStore = new FakeAppleStateStore();
    excludedStore.acquireEnabled = false;
    const history = new FakeHistory(() => Ok({ notifications: [], hasMore: false, cursorAfter: 'terminal' }));
    const excluded = await runner(history, excludedStore, new FakeIntake([])).runCycle(new AbortController().signal);
    expect(await excluded.unwrap()).toMatchObject({ status: 'excluded' });

    const lostStore = new FakeAppleStateStore();
    lostStore.loseLeaseOnRenewal = 1;
    const lost = await runner(history, lostStore, new FakeIntake([])).runCycle(new AbortController().signal);
    expect(await lost.unwrapErr()).toMatchObject({
      code: 'lease-lost',
      processedNotifications: 0,
    });
    expect(lostStore.releases).toBe(1);
  });

  test('advances a durable cursor after accepted and duplicate intake outcomes', async () => {
    const store = new FakeAppleStateStore();
    const history = new FakeHistory(cursor =>
      cursor === undefined
        ? Ok({
            notifications: [{ signedPayload: 'signed-one' }, { signedPayload: 'signed-two' }],
            cursorAfter: 'cursor-2',
            hasMore: false,
          })
        : Ok({
            notifications: [],
            hasMore: false,
            cursorAfter: 'cursor-3',
          }),
    );
    const intake = new FakeIntake([
      Ok({ kind: 'accepted', eventId: 'event-1' }),
      Ok({
        kind: 'duplicate',
        dedupId: 'dedup-2',
        eventId: 'event-2',
      }),
    ]);
    const first = await runner(history, store, intake).runCycle(new AbortController().signal);

    expect(await first.unwrap()).toMatchObject({
      status: 'completed',
      processedNotifications: 2,
      state: { cursor: 'cursor-2' },
    });
    expect(store.advances).toEqual(['cursor-2']);
    // Both the accepted and duplicate original event ids are acknowledged —
    // this is what makes their delivery jobs ready-queue eligible — and every
    // acknowledgement precedes the page cursor advance.
    expect(intake.acknowledged).toEqual(['event-1', 'event-2']);
    expect(intake.requests.map(request => JSON.parse(new TextDecoder().decode(request.rawBody)))).toEqual([
      { signedPayload: 'signed-one' },
      { signedPayload: 'signed-two' },
    ]);
    expect(intake.requests[0]).toMatchObject({
      path: options.intakePath,
      headers: { 'content-type': 'application/json' },
    });

    const second = await runner(history, store, new FakeIntake([])).runCycle(new AbortController().signal);
    expect(await second.unwrap()).toMatchObject({ status: 'completed' });
    expect(history.cursors).toEqual([undefined, 'cursor-2']);
  });

  test('retains the cursor on intake failure and cancellation after durable intake', async () => {
    const failedStore = new FakeAppleStateStore();
    failedStore.state = {
      cursor: 'cursor-0',
      consecutiveMissedCycles: 0,
      alert: false,
    };
    const history = new FakeHistory(() =>
      Ok({
        notifications: [{ signedPayload: 'signed-one' }, { signedPayload: 'signed-two' }],
        hasMore: false,
        cursorAfter: 'cursor-1',
      }),
    );
    const failed = await runner(
      history,
      failedStore,
      new FakeIntake([
        Ok({ kind: 'accepted', eventId: 'durable-event' }),
        Err({
          code: 'persistence-unavailable',
          message: 'database unavailable',
        }),
      ]),
    ).runCycle(new AbortController().signal);
    expect(await failed.unwrapErr()).toMatchObject({
      code: 'intake-failed',
      processedNotifications: 1,
      state: { cursor: 'cursor-0' },
    });
    expect(failedStore.advances).toEqual([]);

    const cancelledStore = new FakeAppleStateStore();
    cancelledStore.state = {
      cursor: 'cursor-0',
      consecutiveMissedCycles: 0,
      alert: false,
    };
    const controller = new AbortController();
    const cancelled = await runner(
      history,
      cancelledStore,
      new FakeIntake([Ok({ kind: 'accepted', eventId: 'durable-event' })], () => controller.abort()),
    ).runCycle(controller.signal);
    expect(await cancelled.unwrap()).toMatchObject({
      status: 'cancelled',
      state: { cursor: 'cursor-0' },
    });
    expect(cancelledStore.advances).toEqual([]);
  });

  test('retains the cursor and retries when acknowledgement fails after persistence', async () => {
    const store = new FakeAppleStateStore();
    store.state = { cursor: 'cursor-0', consecutiveMissedCycles: 0, alert: false };
    const history = new FakeHistory(() =>
      Ok({
        notifications: [{ signedPayload: 'signed-one' }],
        hasMore: false,
        cursorAfter: 'cursor-1',
      }),
    );
    const intake = new FakeIntake([Ok({ kind: 'accepted', eventId: 'durable-event' })], undefined, [
      Err({ code: 'persistence-unavailable', message: 'acknowledgement store unavailable' }),
    ]);

    const result = await runner(history, store, intake).runCycle(new AbortController().signal);

    // Persisted-but-unacknowledged is a retryable miss that must not count the
    // item or advance the cursor; the next cycle replays and re-acknowledges.
    expect(await result.unwrapErr()).toMatchObject({
      code: 'intake-failed',
      retryable: true,
      processedNotifications: 0,
      state: { cursor: 'cursor-0' },
    });
    expect(intake.acknowledged).toEqual(['durable-event']);
    expect(store.advances).toEqual([]);
  });

  test('alerts after more than two consecutive missed cycles and resets on success', async () => {
    const store = new FakeAppleStateStore();
    const failingHistory = new FakeHistory(() =>
      Err({
        code: 'server-api-unavailable',
        message: 'provider failed',
        retryable: true,
      }),
    );
    for (let cycle = 1; cycle <= 3; cycle += 1) {
      const result = await runner(failingHistory, store, new FakeIntake([])).runCycle(new AbortController().signal);
      const failure = await result.unwrapErr();
      expect(failure.state?.consecutiveMissedCycles).toBe(cycle);
      expect(failure.state?.alert).toBe(cycle > 2);
    }

    const successfulHistory = new FakeHistory(() => Ok({ notifications: [], hasMore: false, cursorAfter: 'terminal' }));
    const result = await runner(successfulHistory, store, new FakeIntake([])).runCycle(new AbortController().signal);
    expect(await result.unwrap()).toMatchObject({
      status: 'completed',
      state: { consecutiveMissedCycles: 0, alert: false },
    });
  });

  test('contains state-store failures behind a credential-safe typed error', async () => {
    const store = new FakeAppleStateStore();
    store.acquireLease = async () => Err(storeFailure);
    const result = await runner(
      new FakeHistory(() =>
        Ok({
          notifications: [],
          hasMore: false,
          cursorAfter: 'terminal',
        }),
      ),
      store,
      new FakeIntake([]),
    ).runCycle(new AbortController().signal);
    expect(await result.unwrapErr()).toEqual({
      code: 'state-store-failed',
      message: 'Apple backfill state store failed (unavailable)',
      retryable: true,
      processedNotifications: 0,
    });
  });
});
