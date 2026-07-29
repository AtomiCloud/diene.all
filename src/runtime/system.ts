import { randomUUID } from 'node:crypto';
import type { Clock, IdentifierFactory } from '../domain/index.ts';

export class SystemClock implements Clock {
  nowMs(): number {
    return Date.now();
  }
}

export class RandomIdentifierFactory implements IdentifierFactory {
  create(): string {
    return randomUUID();
  }
}
