import { describe, it } from 'bun:test';
import { portError, type VfsError } from '@atomicloud/diene.interfaces';
import { InMemoryVirtualFileSystem } from '@atomicloud/diene.interfaces/test-helper';
import 'should';
import { runFailInjectionContract, runSequenceContract, runSnapshotIsolationContract } from './contract/behaviours.js';
import { expectErr, expectOk } from './support/capture.js';

const bytes = (...values: number[]): Uint8Array => new Uint8Array(values);
const vfs = (): InMemoryVirtualFileSystem => new InMemoryVirtualFileSystem();
const ioError = (operation: string): VfsError => portError('vfs', 'io', operation, 'disk fault');

describe('InMemoryVirtualFileSystem readFile', () => {
  it('should reject an invalid path', async () => {
    const error = await expectErr(vfs().readFile('relative'));
    error.code.should.eql('invalid-input');
  });

  it('should read back written bytes as an independent copy', async () => {
    const subject = vfs();
    await expectOk(subject.writeFile('/f', bytes(1, 2, 3)));
    const read = await expectOk(subject.readFile('/f'));
    read[0] = 9;
    Array.from(await expectOk(subject.readFile('/f'))).should.eql([1, 2, 3]);
  });

  it('should surface not-found for a missing file', async () => {
    (await expectErr(vfs().readFile('/missing'))).code.should.eql('not-found');
  });

  it('should surface not-a-file for a directory', async () => {
    const subject = vfs();
    await expectOk(subject.createDirectory('/d'));
    (await expectErr(subject.readFile('/d'))).code.should.eql('not-a-file');
  });

  it('should surface an injected failure before touching the node', async () => {
    const subject = vfs();
    subject.failNext(ioError('readFile'));
    (await expectErr(subject.readFile('/whatever'))).code.should.eql('io');
  });
});

describe('InMemoryVirtualFileSystem writeFile', () => {
  it('should reject an invalid path', async () => {
    (await expectErr(vfs().writeFile('bad', bytes(1)))).code.should.eql('invalid-input');
  });

  it('should reject non-Uint8Array contents', async () => {
    const error = await expectErr(vfs().writeFile('/f', [1] as unknown as Uint8Array));
    error.details.should.eql({ field: 'contents' });
  });

  it('should surface an injected failure', async () => {
    const subject = vfs();
    subject.failNext(ioError('writeFile'));
    (await expectErr(subject.writeFile('/f', bytes(1)))).code.should.eql('io');
  });

  it('should refuse to overwrite a directory with a file', async () => {
    const subject = vfs();
    await expectOk(subject.createDirectory('/d'));
    (await expectErr(subject.writeFile('/d', bytes(1)))).code.should.eql('not-a-file');
  });

  it('should require an existing parent directory', async () => {
    (await expectErr(vfs().writeFile('/missing/f', bytes(1)))).code.should.eql('not-a-directory');
  });

  it('should store a frozen defensive copy detached from the caller', async () => {
    const subject = vfs();
    const source = bytes(1, 2);
    await expectOk(subject.writeFile('/f', source));
    source[0] = 9;
    Array.from(await expectOk(subject.readFile('/f'))).should.eql([1, 2]);
  });
});

describe('InMemoryVirtualFileSystem exists', () => {
  it('should reject an invalid path', async () => {
    (await expectErr(vfs().exists('bad'))).code.should.eql('invalid-input');
  });

  it('should report presence and absence', async () => {
    const subject = vfs();
    await expectOk(subject.writeFile('/f', bytes(1)));
    (await expectOk(subject.exists('/f'))).should.be.true();
    (await expectOk(subject.exists('/nope'))).should.be.false();
  });

  it('should surface an injected failure', async () => {
    const subject = vfs();
    subject.failNext(ioError('exists'));
    (await expectErr(subject.exists('/f'))).code.should.eql('io');
  });
});

describe('InMemoryVirtualFileSystem stat', () => {
  it('should reject an invalid path', async () => {
    (await expectErr(vfs().stat('bad'))).code.should.eql('invalid-input');
  });

  it('should surface an injected failure', async () => {
    const subject = vfs();
    subject.failNext(ioError('stat'));
    (await expectErr(subject.stat('/')).then(e => e.code)).should.eql('io');
  });

  it('should surface not-found for a missing path', async () => {
    (await expectErr(vfs().stat('/missing'))).code.should.eql('not-found');
  });

  it('should report file size and zero-size directories', async () => {
    const subject = vfs();
    await expectOk(subject.writeFile('/f', bytes(1, 2, 3, 4)));
    (await expectOk(subject.stat('/f'))).should.eql({ kind: 'file', size: 4 });
    (await expectOk(subject.stat('/'))).should.eql({ kind: 'directory', size: 0 });
  });
});

describe('InMemoryVirtualFileSystem list', () => {
  it('should reject an invalid path', async () => {
    (await expectErr(vfs().list('bad'))).code.should.eql('invalid-input');
  });

  it('should surface an injected failure', async () => {
    const subject = vfs();
    subject.failNext(ioError('list'));
    (await expectErr(subject.list('/'))).code.should.eql('io');
  });

  it('should surface not-found for a missing directory', async () => {
    (await expectErr(vfs().list('/missing'))).code.should.eql('not-found');
  });

  it('should surface not-a-directory for a file', async () => {
    const subject = vfs();
    await expectOk(subject.writeFile('/f', bytes(1)));
    (await expectErr(subject.list('/f'))).code.should.eql('not-a-directory');
  });

  it('should list only direct children, sorted, excluding deeper descendants', async () => {
    const subject = vfs();
    await expectOk(subject.createDirectory('/a'));
    await expectOk(subject.createDirectory('/a/sub'));
    await expectOk(subject.writeFile('/a/file', bytes(1)));
    await expectOk(subject.writeFile('/a/sub/deep', bytes(1)));

    const entries = await expectOk(subject.list('/a'));
    entries.should.eql([
      { kind: 'file', name: 'file' },
      { kind: 'directory', name: 'sub' },
    ]);
  });

  it('should list children of the root using the root prefix', async () => {
    const subject = vfs();
    await expectOk(subject.writeFile('/top', bytes(1)));
    const entries = await expectOk(subject.list('/'));
    entries.should.eql([{ kind: 'file', name: 'top' }]);
  });

  it('should sort many children written in reverse order', async () => {
    // Arrange - three children inserted out of order forces real comparator work
    const subject = vfs();
    await expectOk(subject.writeFile('/zed', bytes(1)));
    await expectOk(subject.writeFile('/mid', bytes(1)));
    await expectOk(subject.writeFile('/abc', bytes(1)));

    // Act / Assert
    (await expectOk(subject.list('/'))).map(entry => entry.name).should.eql(['abc', 'mid', 'zed']);
  });
});

describe('InMemoryVirtualFileSystem createDirectory', () => {
  it('should reject an invalid path', async () => {
    (await expectErr(vfs().createDirectory('bad'))).code.should.eql('invalid-input');
  });

  it('should reject a non-boolean recursive option', async () => {
    const error = await expectErr(vfs().createDirectory('/d', { recursive: 'x' as unknown as boolean }));
    error.details.should.eql({ field: 'recursive' });
  });

  it('should surface an injected failure', async () => {
    const subject = vfs();
    subject.failNext(ioError('createDirectory'));
    (await expectErr(subject.createDirectory('/d'))).code.should.eql('io');
  });

  it('should refuse to create a directory where a file exists', async () => {
    const subject = vfs();
    await expectOk(subject.writeFile('/f', bytes(1)));
    (await expectErr(subject.createDirectory('/f'))).code.should.eql('not-a-directory');
  });

  it('should be idempotent on an existing directory only when recursive', async () => {
    const subject = vfs();
    await expectOk(subject.createDirectory('/d'));
    await expectOk(subject.createDirectory('/d', { recursive: true }));
    (await expectErr(subject.createDirectory('/d'))).code.should.eql('already-exists');
  });

  it('should create ancestors recursively but stop at a file ancestor', async () => {
    const subject = vfs();
    await expectOk(subject.createDirectory('/a/b/c', { recursive: true }));
    (await expectOk(subject.stat('/a/b'))).kind.should.eql('directory');

    await expectOk(subject.writeFile('/file', bytes(1)));
    (await expectErr(subject.createDirectory('/file/x', { recursive: true }))).code.should.eql('not-a-directory');
  });

  it('should require an existing parent when non-recursive', async () => {
    (await expectErr(vfs().createDirectory('/x/y'))).code.should.eql('not-a-directory');
  });

  it('should create a directory under an existing parent', async () => {
    const subject = vfs();
    await expectOk(subject.createDirectory('/z'));
    (await expectOk(subject.stat('/z'))).kind.should.eql('directory');
  });
});

describe('InMemoryVirtualFileSystem remove', () => {
  it('should reject an invalid path', async () => {
    (await expectErr(vfs().remove('bad'))).code.should.eql('invalid-input');
  });

  it('should reject a non-boolean recursive option', async () => {
    const error = await expectErr(vfs().remove('/d', { recursive: 'x' as unknown as boolean }));
    error.details.should.eql({ field: 'recursive' });
  });

  it('should surface an injected failure', async () => {
    const subject = vfs();
    subject.failNext(ioError('remove'));
    (await expectErr(subject.remove('/d'))).code.should.eql('io');
  });

  it('should refuse to remove the root', async () => {
    (await expectErr(vfs().remove('/'))).code.should.eql('unsupported');
  });

  it('should surface not-found for a missing path', async () => {
    (await expectErr(vfs().remove('/missing'))).code.should.eql('not-found');
  });

  it('should refuse to remove a non-empty directory without recursive', async () => {
    const subject = vfs();
    await expectOk(subject.createDirectory('/d'));
    await expectOk(subject.writeFile('/d/f', bytes(1)));
    (await expectErr(subject.remove('/d'))).code.should.eql('directory-not-empty');
  });

  it('should remove a directory tree recursively', async () => {
    const subject = vfs();
    await expectOk(subject.createDirectory('/d'));
    await expectOk(subject.writeFile('/d/f', bytes(1)));
    await expectOk(subject.remove('/d', { recursive: true }));
    (await expectOk(subject.exists('/d'))).should.be.false();
    (await expectOk(subject.exists('/d/f'))).should.be.false();
  });

  it('should remove a file and an empty directory', async () => {
    const subject = vfs();
    await expectOk(subject.writeFile('/f', bytes(1)));
    await expectOk(subject.remove('/f'));
    await expectOk(subject.createDirectory('/e'));
    await expectOk(subject.remove('/e'));
    (await expectOk(subject.exists('/f'))).should.be.false();
    (await expectOk(subject.exists('/e'))).should.be.false();
  });
});

describe('InMemoryVirtualFileSystem recorded state', () => {
  it('should clone writeFile contents in the calls getter', async () => {
    const subject = vfs();
    await expectOk(subject.writeFile('/f', bytes(1, 2)));
    await expectOk(subject.exists('/f'));

    const calls = subject.calls;
    const writeCall = calls[0];
    if (writeCall?.method !== 'writeFile') throw new Error('expected writeFile call');
    writeCall.contents[0] = 9;
    const reread = subject.calls[0];
    if (reread?.method !== 'writeFile') throw new Error('expected writeFile call');
    Array.from(reread.contents).should.eql([1, 2]);
    calls[1]?.method.should.eql('exists');
  });

  it('should expose files in code-unit order with independent byte copies', async () => {
    // Arrange - keys whose locale order (a, B, Z) differs from code-unit order (B, Z, a)
    const subject = vfs();
    await expectOk(subject.writeFile('/a', bytes(1)));
    await expectOk(subject.writeFile('/Z', bytes(2)));
    await expectOk(subject.writeFile('/B', bytes(3)));

    // Assert - deterministic, locale-independent code-unit ordering: 'B'(66) < 'Z'(90) < 'a'(97)
    const files = subject.files;
    Object.keys(files).should.eql(['/B', '/Z', '/a']);
    (files['/a'] as Uint8Array)[0] = 9;
    Array.from(subject.files['/a'] as Uint8Array).should.eql([1]);
  });

  it('should satisfy the sequence contract across mixed calls', async () => {
    const subject = vfs();
    await runSequenceContract({
      label: 'InMemoryVirtualFileSystem',
      record: async () => {
        await subject.exists('/probe');
      },
      sequences: () => subject.calls.map(call => call.sequence),
    });
  });

  it('should satisfy the one-shot fault-injection contract', async () => {
    const subject = vfs();
    await expectOk(subject.writeFile('/f', bytes(1)));
    await runFailInjectionContract({
      label: 'InMemoryVirtualFileSystem',
      makeError: () => ioError('exists'),
      injectFailure: error => subject.failNext(error),
      callFallible: () => subject.exists('/f'),
    });
  });

  it('should satisfy the snapshot isolation contract', async () => {
    const subject = vfs();
    await runSnapshotIsolationContract({
      label: 'InMemoryVirtualFileSystem',
      produce: async () => {
        await subject.exists('/probe');
      },
      readSnapshot: () => subject.calls,
    });
  });
});
