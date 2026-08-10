import { Temporal } from '@js-temporal/polyfill';
import { z } from 'zod';
import { fromWire, reminderWireSchema, toWire } from '@/lib/domain/codec';
import { isDue } from '@/lib/domain/reminder';
import { createTracker } from '@/lib/tracker';

const requestSchema = z.object({ reminder: reminderWireSchema }).strict();

/**
 * Sample three-layer endpoint: wire (C0 strings) → codec → domain (Temporal
 * values) → logic → codec → wire. The transport-codec gate exercises the same
 * codecs; this route is the production consumer that proves the shape.
 */
export async function POST(request: Request): Promise<Response> {
  const parsed = requestSchema.safeParse(await request.json().catch(() => undefined));
  if (!parsed.success) {
    return Response.json({ title: 'Validation Error', status: 400 }, { status: 400 });
  }

  const tracker = createTracker();
  tracker.subscribe(() => {
    // The template wires tracker events to faro server-side; sample no-ops.
  });
  tracker.track({ name: 'reminder_checked' });

  const reminder = fromWire(parsed.data.reminder);
  const due = isDue(reminder, Temporal.Now.instant());
  return Response.json({ due, reminder: toWire(reminder) });
}
