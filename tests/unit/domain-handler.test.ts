import { describe, it } from 'bun:test';
import { Err, Ok, type Result } from '@atomicloud/diene.e2e/result';
import type { StoredObject } from '@atomicloud/diene.e2e/standard-config';
import should from 'should';
import {
  DomainError,
  type EncryptedBlobStorage,
  type MessageRepository,
  SampleWorkerHandler,
} from '../../src/domain/handler';
import { EncryptionError, type IEncryptor } from '../../src/lib/encryption';

const message = {
  createdAt: '2026-07-25T06:30:00Z',
  id: '11d8ab19-cdc7-4bc4-a178-70a352c352e8',
  payload: 'hello',
};

class FakeEncryptor implements IEncryptor {
  constructor(readonly failure?: EncryptionError) {}
  decrypt(): Result<string, EncryptionError> {
    return Ok('unused');
  }
  encrypt(): Result<string, EncryptionError> {
    return this.failure ? Err(this.failure) : Ok('encrypted');
  }
}

class FakeStorage implements EncryptedBlobStorage {
  readonly inputs: { readonly body: string; readonly contentType: string; readonly key: string }[] = [];
  constructor(readonly failure?: Error) {}
  save(input: {
    readonly body: string;
    readonly contentType: string;
    readonly key: string;
  }): Result<StoredObject, Error> {
    this.inputs.push(input);
    return this.failure ? Err(this.failure) : Ok({ key: input.key, link: `memory://${input.key}` });
  }
}

class FakeRepository implements MessageRepository {
  readonly records: unknown[] = [];
  constructor(readonly failure?: Error) {}
  insert(record: unknown): Result<boolean, Error> {
    this.records.push(record);
    return this.failure ? Err(this.failure) : Ok(true);
  }
}

describe('SampleWorkerHandler', () => {
  it('should encrypt, store, and persist a worker message', async () => {
    // Arrange
    const repository = new FakeRepository();
    const storage = new FakeStorage();
    const subject = new SampleWorkerHandler(repository, storage, new FakeEncryptor(), 'processed');

    // Act
    const actual = await subject.handle(message).match({ err: error => Promise.reject(error), ok: value => value });

    // Assert
    should(actual).deepEqual({
      inserted: true,
      objectKey: 'processed/11d8ab19-cdc7-4bc4-a178-70a352c352e8.json.enc',
    });
    should(storage.inputs).have.length(1);
    should(repository.records).have.length(1);
  });

  it.each([
    {
      stage: 'encryption',
      encryptor: new FakeEncryptor(new EncryptionError('bad')),
      storage: new FakeStorage(),
      repository: new FakeRepository(),
    },
    {
      stage: 'storage',
      encryptor: new FakeEncryptor(),
      storage: new FakeStorage(new Error('down')),
      repository: new FakeRepository(),
    },
    {
      stage: 'persistence',
      encryptor: new FakeEncryptor(),
      storage: new FakeStorage(),
      repository: new FakeRepository(new Error('down')),
    },
  ])('should map a $stage failure to DomainError', async ({ encryptor, repository, storage }) => {
    // Arrange
    const subject = new SampleWorkerHandler(repository, storage, encryptor, 'processed');

    // Act
    const actual = await subject.handle(message).match({ err: error => error, ok: () => undefined });

    // Assert
    should(actual).be.instanceOf(DomainError);
  });
});
