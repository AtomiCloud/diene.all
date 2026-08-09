import type { StorageEntry } from '@atomicloud/diene.e2e/standard-config';

export interface BucketProvisioner {
  ensure(entry: StorageEntry): Promise<void>;
}

export class McBucketProvisioner implements BucketProvisioner {
  constructor(readonly executable = 'mc') {}

  async ensure(entry: StorageEntry): Promise<void> {
    const alias = `diene-${Bun.hash(entry.endpoint).toString(16)}`;
    const configure = Bun.spawn(
      [this.executable, 'alias', 'set', alias, entry.endpoint, entry.accessKeyId, entry.secretAccessKey],
      { stderr: 'pipe', stdout: 'pipe' },
    );
    const configureCode = await configure.exited;
    if (configureCode !== 0)
      throw new Error(`storage alias setup failed: ${await new Response(configure.stderr).text()}`);
    const create = Bun.spawn([this.executable, 'mb', '--ignore-existing', `${alias}/${entry.bucket}`], {
      stderr: 'pipe',
      stdout: 'pipe',
    });
    const createCode = await create.exited;
    if (createCode !== 0) throw new Error(`bucket creation failed: ${await new Response(create.stderr).text()}`);
  }
}
