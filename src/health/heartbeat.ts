import { mkdir } from 'node:fs/promises';
import { dirname } from 'node:path';
import { z } from 'zod';

const heartbeatSchema = z
  .object({
    pid: z.number().int().positive(),
    state: z.enum(['healthy', 'starting', 'stopping']),
    timestamp: z.iso.datetime({ offset: true }),
  })
  .strict();

export type Heartbeat = z.infer<typeof heartbeatSchema>;

export interface HealthResult {
  readonly ageMs?: number;
  readonly healthy: boolean;
  readonly reason: string;
}

export class FileHeartbeat {
  constructor(
    readonly path: string,
    readonly maxAgeMs: number,
    readonly now: () => Date = () => new Date(),
  ) {}

  async write(state: Heartbeat['state']): Promise<void> {
    await mkdir(dirname(this.path), { recursive: true });
    const heartbeat = heartbeatSchema.parse({
      pid: process.pid,
      state,
      timestamp: this.now().toISOString(),
    });
    await Bun.write(this.path, JSON.stringify(heartbeat));
  }

  async check(): Promise<HealthResult> {
    try {
      const heartbeat = heartbeatSchema.parse(await Bun.file(this.path).json());
      const ageMs = this.now().getTime() - new Date(heartbeat.timestamp).getTime();
      const healthy = heartbeat.state === 'healthy' && ageMs >= 0 && ageMs <= this.maxAgeMs;
      return { ageMs, healthy, reason: healthy ? 'heartbeat healthy' : 'heartbeat stale or stopping' };
    } catch (error) {
      return { healthy: false, reason: error instanceof Error ? error.message : String(error) };
    }
  }
}
