import { describe, it } from 'bun:test';
import {
  type ProcessOutput,
  type ProcessRequest,
  validateProcessOutput,
  validateProcessRequest,
} from '@atomicloud/diene.interfaces';
import 'should';
import { expectErr, expectOk } from './support/result.js';

describe('validateProcessRequest', () => {
  it('should accept a bare executable and freeze the normalized request', async () => {
    // Act
    const actual = await expectOk(validateProcessRequest({ executable: 'ls' }));

    // Assert - no optional keys are serialized when absent
    actual.should.eql({ executable: 'ls' });
    Object.isFrozen(actual).should.be.true();
  });

  it('should deep-copy and freeze every optional field when present', async () => {
    // Arrange
    const args = ['-a', '-l'];
    const env = { PATH: '/bin' };
    const request: ProcessRequest = {
      executable: 'ls',
      arguments: args,
      cwd: '/home',
      environment: env,
      stdin: 'input',
      timeoutMs: 1000,
    };

    // Act
    const actual = await expectOk(validateProcessRequest(request));

    // Assert - detached, frozen copies
    actual.should.eql(request);
    Object.isFrozen(actual.arguments).should.be.true();
    Object.isFrozen(actual.environment).should.be.true();
    (actual.arguments === args).should.be.false();
    (actual.environment === env).should.be.false();
  });

  it.each([
    ['null', null as unknown as ProcessRequest],
    ['a primitive', 4 as unknown as ProcessRequest],
  ])('should reject a non-object request (%s)', async (_label, request) => {
    const error = await expectErr(validateProcessRequest(request));
    error.port.should.eql('system');
    error.operation.should.eql('execute');
    error.details.should.eql({ field: 'request' });
  });

  it.each([
    ['non-string', 5 as unknown as string],
    ['blank', '   '],
    ['empty', ''],
  ])('should reject a blank executable (%s)', async (_label, executable) => {
    const error = await expectErr(validateProcessRequest({ executable }));
    error.details.should.eql({ field: 'executable' });
    error.message.should.match(/must not be blank/);
  });

  it('should reject an executable containing NUL', async () => {
    const error = await expectErr(validateProcessRequest({ executable: 'ls\0rm' }));
    error.details.should.eql({ field: 'executable' });
    error.message.should.match(/must not contain NUL/);
  });

  it.each([
    ['not an array', 'nope' as unknown as string[]],
    ['non-string element', [1] as unknown as string[]],
    ['NUL element', ['a\0b']],
  ])('should reject invalid arguments (%s)', async (_label, args) => {
    const error = await expectErr(validateProcessRequest({ executable: 'ls', arguments: args }));
    error.details.should.eql({ field: 'arguments' });
  });

  it.each([
    ['non-string', 5 as unknown as string],
    ['empty', ''],
    ['NUL', '/a\0b'],
  ])('should reject an invalid cwd (%s)', async (_label, cwd) => {
    const error = await expectErr(validateProcessRequest({ executable: 'ls', cwd }));
    error.details.should.eql({ field: 'cwd' });
  });

  it.each([
    ['null', null as unknown as Record<string, string>],
    ['an array', [] as unknown as Record<string, string>],
    ['a primitive', 3 as unknown as Record<string, string>],
    ['a Date', new Date() as unknown as Record<string, string>],
    ['a class instance', new (class Env {})() as unknown as Record<string, string>],
  ])('should reject a non-record environment (%s)', async (_label, environment) => {
    const error = await expectErr(validateProcessRequest({ executable: 'ls', environment }));
    error.details.should.eql({ field: 'environment' });
    error.message.should.match(/must be a string record/);
  });

  it.each([
    ['empty key', { '': 'v' }],
    ['key with =', { 'A=B': 'v' }],
    ['key with NUL', { 'A\0': 'v' }],
    ['non-string value', { A: 1 as unknown as string }],
    ['value with NUL', { A: 'v\0' }],
  ])('should reject invalid environment entries (%s)', async (_label, environment) => {
    const error = await expectErr(validateProcessRequest({ executable: 'ls', environment }));
    error.details.should.eql({ field: 'environment' });
    error.message.should.match(/entries must be valid/);
  });

  it('should reject a non-string stdin', async () => {
    const error = await expectErr(validateProcessRequest({ executable: 'ls', stdin: 5 as unknown as string }));
    error.details.should.eql({ field: 'stdin' });
  });

  it.each([
    ['non-integer', 1.5],
    ['zero', 0],
    ['negative', -1],
  ])('should reject an invalid timeoutMs (%s)', async (_label, timeoutMs) => {
    const error = await expectErr(validateProcessRequest({ executable: 'ls', timeoutMs }));
    error.details.should.eql({ field: 'timeoutMs' });
  });
});

describe('validateProcessOutput', () => {
  it('should accept and freeze a well-formed output', async () => {
    // Act
    const actual = await expectOk(validateProcessOutput({ exitCode: 0, stdout: 'out', stderr: '' }));

    // Assert
    actual.should.eql({ exitCode: 0, stdout: 'out', stderr: '' });
    Object.isFrozen(actual).should.be.true();
  });

  it('should accept a non-zero exit code as an ordinary value', async () => {
    const actual = await expectOk(validateProcessOutput({ exitCode: 127, stdout: '', stderr: 'not found' }));
    actual.exitCode.should.eql(127);
  });

  it.each([
    ['null', null as unknown as ProcessOutput],
    ['non-integer exit', { exitCode: 1.2, stdout: '', stderr: '' }],
    ['non-string stdout', { exitCode: 0, stdout: 1 as unknown as string, stderr: '' }],
    ['non-string stderr', { exitCode: 0, stdout: '', stderr: 1 as unknown as string }],
  ])('should reject malformed output (%s)', async (_label, output) => {
    const error = await expectErr(validateProcessOutput(output as ProcessOutput));
    error.port.should.eql('system');
    error.message.should.match(/integer exit code and text streams/);
  });
});
