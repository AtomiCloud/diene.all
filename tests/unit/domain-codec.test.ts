import { describe, it } from 'bun:test';
import { Temporal } from '@js-temporal/polyfill';
import should from 'should';
import { fromWire, reminderWireSchema, toWire } from '../../src/lib/domain/codec';
import { isDue, nextOccurrence, type Reminder } from '../../src/lib/domain/reminder';

const reminder: Reminder = {
  id: 'r1',
  title: 'Stand up',
  remindAt: Temporal.Instant.from('2026-07-25T09:00:00Z'),
  leadTime: Temporal.Duration.from({ minutes: 10 }),
};

describe('toWire/fromWire', () => {
  it('should round-trip a reminder through the C0 wire shape', () => {
    // Arrange

    // Act
    const wire = toWire(reminder);
    const actual = fromWire(wire);

    // Assert
    should(actual.id).equal(reminder.id);
    should(actual.title).equal(reminder.title);
    should(Temporal.Instant.compare(actual.remindAt, reminder.remindAt)).equal(0);
    should(Temporal.Duration.compare(actual.leadTime, reminder.leadTime, { relativeTo: '2026-01-01' })).equal(0);
  });

  it('should emit C0 string formats on the wire', () => {
    // Arrange

    // Act
    const wire = toWire(reminder);

    // Assert
    should(wire.remindAt).be.a.String();
    should(wire.leadTime).be.a.String();
    should(reminderWireSchema.safeParse(wire).success).be.true();
  });

  it('should reject a malformed wire payload', () => {
    // Arrange
    const malformed = { id: '', title: '', remindAt: '', leadTime: '' };

    // Act
    const actual = reminderWireSchema.safeParse(malformed);

    // Assert
    should(actual.success).be.false();
  });
});

describe('isDue', () => {
  it.each([
    { now: '2026-07-25T08:49:59Z', expected: false },
    { now: '2026-07-25T08:50:00Z', expected: true },
    { now: '2026-07-25T09:30:00Z', expected: true },
  ])('should report due=$expected at $now (lead time 10m)', ({ now, expected }) => {
    // Arrange
    const instant = Temporal.Instant.from(now);

    // Act
    const actual = isDue(reminder, instant);

    // Assert
    should(actual).equal(expected);
  });
});

describe('nextOccurrence', () => {
  it('should step remindAt by the interval and keep identity', () => {
    // Arrange
    const interval = Temporal.Duration.from({ hours: 24 });

    // Act
    const actual = nextOccurrence(reminder, interval);

    // Assert
    should(actual.id).equal(reminder.id);
    should(Temporal.Instant.compare(actual.remindAt, Temporal.Instant.from('2026-07-26T09:00:00Z'))).equal(0);
  });
});
