import type { Result } from '@atomicloud/diene.result';
import { z } from 'zod';
import { keyedPreset } from './keyed';

/**
 * A single named S3-compatible object-storage endpoint (Tigris in prod, MinIO
 * locally). Provider-agnostic connection block — the landscape matrix picks the
 * provider (`goals/garden-environments.md`), the shape stays the same.
 *
 * `accessKeyId` / `secretAccessKey` are secrets: blank-in-yaml (R14/M33).
 * `forcePathStyle` is `true` for MinIO and other path-style endpoints, `false`
 * for virtual-hosted-style providers such as Tigris.
 */
export const storageEntry = z.object({
  /** S3-compatible endpoint URL (e.g. `https://fly.storage.tigris.dev`). */
  endpoint: z.string().min(1),
  /** Region label the endpoint expects. */
  region: z.string().min(1),
  /** Bucket name. */
  bucket: z.string().min(1),
  /** Secret — blank-in-yaml, injected per landscape (R14/M33). */
  accessKeyId: z.string(),
  /** Secret — blank-in-yaml, injected per landscape (R14/M33). */
  secretAccessKey: z.string(),
  /** Path-style addressing (`true` for MinIO, `false` for virtual-hosted). */
  forcePathStyle: z.boolean(),
});

/** One named storage connection entry. */
export type StorageEntry = z.infer<typeof storageEntry>;

/**
 * The `storage` preset: a keyed map of named S3-compatible endpoints.
 *
 * C0-FROZEN (c0-contracts.md §3): matched key-for-key across bun / dotnet / go.
 */
export const storage = keyedPreset(storageEntry);

/** The resolved `storage` block: `Record<UPPERCASE_NAME, StorageEntry>`. */
export type StorageBlock = z.infer<typeof storage>;

// ─── block-storage interface · the deliberately tiny object surface ─────────────

/** A failure from a block-storage IO operation (upload). */
export class StorageError extends Error {
  constructor(
    message: string,
    /** The underlying cause, when one was thrown. */
    override readonly cause?: unknown,
  ) {
    super(message);
    this.name = 'StorageError';
  }
}

/** An object to upload through {@link BlockStorage.save}. */
export interface SaveInput {
  /** Object key (path within the bucket). */
  key: string;
  /** Object bytes. */
  body: Uint8Array | ArrayBuffer | string;
  /** Optional MIME type stored with the object. */
  contentType?: string;
}

/** A stored object handle returned by {@link BlockStorage.save}. */
export interface StoredObject {
  /** The object key it was stored under. */
  key: string;
  /** The public (unsigned) link to the object. */
  link: string;
}

/** Options for {@link BlockStorage.getSignedUrl}. */
export interface SignedUrlOptions {
  /** Expiry in seconds (default 900 = 15 minutes). */
  expiresIn?: number;
  /** HTTP method the signature authorizes (default `GET`). */
  method?: 'GET' | 'PUT' | 'DELETE' | 'HEAD';
}

/**
 * The block-storage surface: deliberately tiny — upload an object, get a public
 * link, get a signed URL. That is the WHOLE interface. The interface plus the
 * one S3-compatible implementation (`adapters/s3-block-storage.ts`) ship here and
 * are lib-proven; consumers never int-test it.
 */
export interface BlockStorage {
  /**
   * Upload an object/image. Network IO, so it is railway-oriented: a transport
   * failure resolves to `Err<StorageError>` rather than throwing.
   */
  save(input: SaveInput): Promise<Result<StoredObject, StorageError>>;
  /** The public, unsigned link for an object key. Pure — no IO. */
  getLink(key: string): string;
  /**
   * A time-limited signed URL for an object key. Deterministic given the
   * connection block; throws {@link StorageError} only on an environment fault
   * (e.g. the Bun runtime is unavailable to the S3 implementation).
   */
  getSignedUrl(key: string, options?: SignedUrlOptions): string;
}
