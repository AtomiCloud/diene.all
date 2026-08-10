import type { Result } from '@atomicloud/diene.result';
import 'should';
import { expectErr, expectOk } from '../support/capture.js';

// Reusable behavioral contracts for recording effect-port doubles.
//
// Each contract is expressed against a small *driver* interface that describes
// how to exercise a subject, never against a concrete mock. The interfaces
// package ships no reference adapter today, so these run against the in-memory
// doubles — but a future adapter can satisfy the same drivers and inherit the
// suite unchanged.

// ─── Deterministic call sequencing ──────────────────────────────────────────
// Every recording port stamps a strictly increasing, zero-based `sequence` on
// each recorded call, in call order.
interface SequenceDriver {
  readonly label: string;
  record(): Promise<void> | void;
  sequences(): readonly number[];
}

async function runSequenceContract(driver: SequenceDriver): Promise<void> {
  await driver.record();
  await driver.record();
  await driver.record();
  driver.sequences().should.eql([0, 1, 2]);
}

// ─── One-shot fault injection ───────────────────────────────────────────────
// `failNext` arms exactly one failure: the next fallible call fails with the
// injected error, and the call after it succeeds again.
interface FailInjectionDriver<E> {
  readonly label: string;
  makeError(): E;
  injectFailure(error: E): void;
  callFallible(): Result<unknown, E>;
}

async function runFailInjectionContract<E>(driver: FailInjectionDriver<E>): Promise<void> {
  const error = driver.makeError();
  driver.injectFailure(error);
  const failed = await expectErr(driver.callFallible());
  (failed === error).should.be.true();
  // The injection is spent — the very next fallible call is healthy again.
  await expectOk(driver.callFallible());
}

// ─── Snapshot isolation ─────────────────────────────────────────────────────
// Reads of the recorded history hand back a fresh, frozen snapshot each time, so
// a caller can never reach back into the double's internal state.
interface SnapshotDriver {
  readonly label: string;
  produce(): Promise<void> | void;
  readSnapshot(): readonly unknown[];
}

async function runSnapshotIsolationContract(driver: SnapshotDriver): Promise<void> {
  await driver.produce();
  const first = driver.readSnapshot();
  const second = driver.readSnapshot();
  (first === second).should.be.false();
  first.should.eql(second);
  first.length.should.be.aboveOrEqual(1);
  // each recorded entry is a frozen defensive copy (the array wrapper itself need not be)
  Object.isFrozen(first[0]).should.be.true();
}

export { runFailInjectionContract, runSequenceContract, runSnapshotIsolationContract };
