import { Temporal } from '@js-temporal/polyfill';

/**
 * Sample three-layer domain type: the DOMAIN layer holds Temporal-class values
 * exclusively; the wire layer is C0 standardized strings; the codecs in
 * `./codec.ts` convert. Illustrates the pattern every real feature follows.
 */
export interface Reminder {
  readonly id: string;
  readonly title: string;
  /** Domain time is a Temporal.Instant — never a string, never a Date. */
  readonly remindAt: Temporal.Instant;
  /** Lead time before the reminder — a Temporal.Duration. */
  readonly leadTime: Temporal.Duration;
}

/** Is the reminder due at `now`? Pure domain logic on Temporal values. */
export const isDue = (reminder: Reminder, now: Temporal.Instant): boolean =>
  Temporal.Instant.compare(now, reminder.remindAt.subtract(reminder.leadTime)) >= 0;

/** Next occurrence for a repeating reminder stepped by `interval`. */
export const nextOccurrence = (reminder: Reminder, interval: Temporal.Duration): Reminder => ({
  ...reminder,
  remindAt: reminder.remindAt.add(interval),
});
