import type { Result } from '@atomicloud/diene.e2e/result';
import type { StoredObject } from '@atomicloud/diene.e2e/standard-config';
import type { IEncryptor } from '../lib/encryption';
import type { WorkerMessage } from '../lib/message-codec';

export class DomainError extends Error {
  constructor(
    message: string,
    override readonly cause?: unknown,
  ) {
    super(message);
    this.name = 'DomainError';
  }
}

export interface ProcessedMessageRecord {
  readonly createdAt: string;
  readonly id: string;
  readonly objectKey: string;
  readonly payload: string;
}

export interface MessageRepository {
  insert(record: ProcessedMessageRecord): Result<boolean, Error>;
}

export interface EncryptedBlobStorage {
  save(input: {
    readonly body: string;
    readonly contentType: string;
    readonly key: string;
  }): Result<StoredObject, Error>;
}

export interface HandledMessage {
  readonly inserted: boolean;
  readonly objectKey: string;
}

export class SampleWorkerHandler {
  constructor(
    readonly repository: MessageRepository,
    readonly storage: EncryptedBlobStorage,
    readonly encryptor: IEncryptor,
    readonly blobPrefix: string,
  ) {}

  handle(message: WorkerMessage): Result<HandledMessage, DomainError> {
    const objectKey = `${this.blobPrefix}/${message.id}.json.enc`;
    return this.encryptor
      .encrypt(message.payload)
      .mapErr(error => new DomainError('message encryption failed', error))
      .andThen(encrypted =>
        this.storage
          .save({ body: encrypted, contentType: 'application/octet-stream', key: objectKey })
          .mapErr(error => new DomainError('message storage failed', error)),
      )
      .andThen(() =>
        this.repository
          .insert({
            createdAt: message.createdAt,
            id: message.id,
            objectKey,
            payload: message.payload,
          })
          .mapErr(error => new DomainError('message persistence failed', error)),
      )
      .map(inserted => ({ inserted, objectKey }));
  }
}
