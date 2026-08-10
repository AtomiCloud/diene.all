import { describe, it } from 'bun:test';
import {
  type CreateDirectoryOptions,
  checkVfsPath,
  validateCreateDirectoryOptions,
  validateFileContents,
  validateRemoveOptions,
  validateVfsPath,
} from '@atomicloud/diene.interfaces';
import 'should';
import { expectErr, expectOk } from './support/result.js';

describe('validateVfsPath', () => {
  it.each([
    ['a nested path', '/a/b/c'],
    ['the root', '/'],
  ])('should accept a canonical absolute path (%s)', async (_label, path) => {
    const actual = await expectOk(validateVfsPath(path));
    actual.should.eql(path);
  });

  it.each([
    ['non-string', 5 as unknown as string],
    ['empty', ''],
    ['NUL', '/a\0b'],
  ])('should reject a non-usable path (%s)', async (_label, path) => {
    const error = await expectErr(validateVfsPath(path));
    error.port.should.eql('vfs');
    error.details.should.eql({ field: 'path' });
    error.message.should.match(/non-empty NUL-free/);
  });

  it('should reject a relative path', async () => {
    const error = await expectErr(validateVfsPath('a/b'));
    error.message.should.match(/must be absolute/);
  });

  it.each([
    ['trailing slash', '/a/'],
    ['double slash', '/a//b'],
  ])('should reject a non-canonical path (%s)', async (_label, path) => {
    const error = await expectErr(validateVfsPath(path));
    error.message.should.match(/must be canonical/);
  });

  it.each([
    ['single dot', '/a/./b'],
    ['double dot', '/a/../b'],
  ])('should reject dot segments (%s)', async (_label, path) => {
    const error = await expectErr(validateVfsPath(path));
    error.message.should.match(/must not contain dot segments/);
  });

  it('should carry the supplied operation label', async () => {
    const error = await expectErr(validateVfsPath('bad', 'readFile'));
    error.operation.should.eql('readFile');
  });
});

describe('validateFileContents', () => {
  it('should accept and defensively copy Uint8Array bytes', async () => {
    // Arrange
    const source = new Uint8Array([1, 2, 3]);

    // Act
    const actual = await expectOk(validateFileContents(source));
    source[0] = 9;

    // Assert - detached copy, original mutation does not leak
    (actual === source).should.be.false();
    Array.from(actual).should.eql([1, 2, 3]);
  });

  it('should reject non-Uint8Array contents', async () => {
    const error = await expectErr(validateFileContents([1, 2, 3] as unknown as Uint8Array));
    error.port.should.eql('vfs');
    error.operation.should.eql('writeFile');
    error.details.should.eql({ field: 'contents' });
  });
});

describe('recursive option validators', () => {
  it.each([
    ['create', validateCreateDirectoryOptions],
    ['remove', validateRemoveOptions],
  ])('should default undefined options to non-recursive (%s)', async (_label, validate) => {
    const actual = await expectOk(validate(undefined));
    actual.should.eql({ recursive: false });
    Object.isFrozen(actual).should.be.true();
  });

  it.each([
    ['explicit true', { recursive: true }, true],
    ['explicit false', { recursive: false }, false],
    ['empty object', {}, false],
  ])('should normalize a provided recursive flag (%s)', async (_label, options, expected) => {
    const actual = await expectOk(validateCreateDirectoryOptions(options));
    actual.should.eql({ recursive: expected });
  });

  it.each([
    ['null', null as unknown as CreateDirectoryOptions],
    ['an array', [] as unknown as CreateDirectoryOptions],
    ['a primitive', 3 as unknown as CreateDirectoryOptions],
    ['a class instance', new (class Opt {})() as unknown as CreateDirectoryOptions],
  ])('should reject a non-record options object (%s)', async (_label, options) => {
    const error = await expectErr(validateRemoveOptions(options));
    error.port.should.eql('vfs');
    error.operation.should.eql('remove');
    error.details.should.eql({ field: 'options' });
  });

  it('should reject a non-boolean recursive flag with the operation label', async () => {
    const error = await expectErr(validateCreateDirectoryOptions({ recursive: 'yes' as unknown as boolean }));
    error.operation.should.eql('createDirectory');
    error.details.should.eql({ field: 'recursive' });
  });
});

describe('checkVfsPath', () => {
  it('should expose accepted and rejected Checked branches', () => {
    // Act
    const ok = checkVfsPath('/a');
    const bad = checkVfsPath('relative');

    // Assert
    ok.ok.should.be.true();
    if (ok.ok) ok.value.should.eql('/a');
    bad.ok.should.be.false();
    if (!bad.ok) bad.error.operation.should.eql('path');
  });
});
