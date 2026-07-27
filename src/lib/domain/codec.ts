import {
  formatWireDateTime,
  formatWireDuration,
  parseWireDateTime,
  parseWireDuration,
} from '@atomicloud/diene.core-utils';
import { z } from 'zod';
import type { Reminder } from './reminder';

/**
 * C0 wire codecs for the Reminder domain type: the wire shape is standardized
 * strings (core-utils owns the format), the domain shape is Temporal values.
 * The transport codec gate proves both directions round-trip.
 */

export const reminderWireSchema = z
  .object({
    id: z.string().min(1),
    title: z.string().min(1),
    remindAt: z.string().min(1),
    leadTime: z.string().min(1),
  })
  .strict();

export type ReminderWire = z.infer<typeof reminderWireSchema>;

export const toWire = (reminder: Reminder): ReminderWire => ({
  id: reminder.id,
  title: reminder.title,
  remindAt: formatWireDateTime(reminder.remindAt),
  leadTime: formatWireDuration(reminder.leadTime),
});

export const fromWire = (wire: ReminderWire): Reminder => ({
  id: wire.id,
  title: wire.title,
  remindAt: parseWireDateTime(wire.remindAt),
  leadTime: parseWireDuration(wire.leadTime),
});
