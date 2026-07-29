import type { MigrationRunner } from './migrations';
import type { ReachabilityChecks } from './reachability';
import type { SeedLoader } from './seeds';

export class DatabaseInitializer {
  constructor(
    readonly reachability: ReachabilityChecks,
    readonly migrations: MigrationRunner,
    readonly seeds: SeedLoader,
  ) {}

  async run(): Promise<{ readonly seeded: number }> {
    await this.reachability.run();
    await this.migrations.run();
    return { seeded: await this.seeds.run() };
  }
}
