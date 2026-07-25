import { describe, it } from 'bun:test';
import { chmod, mkdir, mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import should from 'should';

interface InstallerResult {
  readonly code: number;
  readonly out: string;
  readonly err: string;
}

class InstallerHarness {
  readonly fakeBin: string;
  readonly fixtureDir: string;
  readonly installDir: string;

  constructor(readonly root: string) {
    this.fakeBin = join(root, 'fake-bin');
    this.fixtureDir = join(root, 'fixture');
    this.installDir = join(root, 'installed');
  }

  async setup(): Promise<void> {
    await mkdir(this.fakeBin, { recursive: true });
    await mkdir(this.fixtureDir, { recursive: true });
    await Bun.write(
      join(this.fakeBin, 'uname'),
      String.raw`#!/usr/bin/env bash
case "${'$'}{1:-}" in
-s) printf "%s\n" "${'$'}{FAKE_OS:-Linux}" ;;
-m) printf "%s\n" "${'$'}{FAKE_ARCH:-x86_64}" ;;
esac
`,
    );
    await Bun.write(
      join(this.fakeBin, 'curl'),
      String.raw`#!/usr/bin/env bash
out=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then out="$2"; shift 2; else shift; fi
done
case "${'$'}{out}" in
*checksums.txt) cp "${'$'}{FIXTURE_DIR}/checksums.txt" "${'$'}{out}" ;;
*) cp "${'$'}{FIXTURE_DIR}/bun-cli_linux_amd64.tar.gz" "${'$'}{out}" ;;
esac
`,
    );
    await chmod(join(this.fakeBin, 'uname'), 0o755);
    await chmod(join(this.fakeBin, 'curl'), 0o755);
  }

  async prepareArchive(validChecksum: boolean): Promise<void> {
    const payload = join(this.root, 'payload');
    const archive = join(this.fixtureDir, 'bun-cli_linux_amd64.tar.gz');
    await mkdir(payload, { recursive: true });
    await Bun.write(join(payload, 'bun-cli'), '#!/usr/bin/env bash\necho bun-cli fixture\n');
    await chmod(join(payload, 'bun-cli'), 0o755);
    const tar = Bun.spawn(['tar', '-czf', archive, '-C', payload, 'bun-cli']);
    should(await tar.exited).equal(0);
    const digestProc = Bun.spawn(['sha256sum', archive], { stdout: 'pipe' });
    const digest = (await new Response(digestProc.stdout).text()).split(' ')[0];
    should(await digestProc.exited).equal(0);
    await Bun.write(
      join(this.fixtureDir, 'checksums.txt'),
      `${validChecksum ? digest : '0'.repeat(64)}  bun-cli_linux_amd64.tar.gz\n`,
    );
  }

  async run(env: Record<string, string> = {}): Promise<InstallerResult> {
    const process = Bun.spawn(['bash', 'scripts/release/install.sh'], {
      env: {
        ...globalThis.process.env,
        PATH: `${this.fakeBin}:${globalThis.process.env.PATH ?? ''}`,
        BIN_DIR: this.installDir,
        FIXTURE_DIR: this.fixtureDir,
        ...env,
      },
      stdout: 'pipe',
      stderr: 'pipe',
    });
    const [out, err, code] = await Promise.all([
      new Response(process.stdout).text(),
      new Response(process.stderr).text(),
      process.exited,
    ]);
    return { code, out, err };
  }

  async cleanup(): Promise<void> {
    await rm(this.root, { recursive: true, force: true });
  }
}

describe('release installer contract', () => {
  it('should reject an unsupported operating system before downloading', async () => {
    // Arrange
    const harness = new InstallerHarness(await mkdtemp(join(tmpdir(), 'bun-cli-installer-')));
    await harness.setup();

    try {
      // Act
      const actual = await harness.run({ FAKE_OS: 'Plan9' });

      // Assert
      should(actual.code).not.equal(0);
      should(actual.err).containEql('unsupported OS');
    } finally {
      await harness.cleanup();
    }
  });

  it('should reject an archive whose checksum does not match', async () => {
    // Arrange
    const harness = new InstallerHarness(await mkdtemp(join(tmpdir(), 'bun-cli-installer-')));
    await harness.setup();
    await harness.prepareArchive(false);

    try {
      // Act
      const actual = await harness.run();

      // Assert
      should(actual.code).not.equal(0);
      should(actual.out + actual.err).containEql('FAILED');
    } finally {
      await harness.cleanup();
    }
  });

  it('should complete the supported installation path after verifying its checksum', async () => {
    // Arrange
    const harness = new InstallerHarness(await mkdtemp(join(tmpdir(), 'bun-cli-installer-')));
    await harness.setup();
    await harness.prepareArchive(true);

    try {
      // Act
      const actual = await harness.run();

      // Assert
      should(actual.code).equal(0);
      should(actual.out).containEql('checksum verified');
      should(await readFile(join(harness.installDir, 'bun-cli'), 'utf8')).containEql('bun-cli fixture');
    } finally {
      await harness.cleanup();
    }
  });
});
