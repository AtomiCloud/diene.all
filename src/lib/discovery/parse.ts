import { isRecord } from '@atomicloud/diene.core-utils';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { malformedDoc } from './errors';
import type { DiscoveryError, DocA, DocB, DocBLandscape, DocC, DocCCandidateList } from './types';

type Doc = 'A' | 'B' | 'C';

const isFiniteNumber = (value: unknown): value is number => typeof value === 'number' && Number.isFinite(value);

const isStringArray = (value: unknown): value is readonly string[] =>
  Array.isArray(value) && value.every(item => typeof item === 'string');

const isStringRecord = (value: unknown): value is Readonly<Record<string, string>> =>
  isRecord(value) && Object.values(value).every(item => typeof item === 'string');

/** Parse Doc A from raw JSON. Returns a typed doc or a `malformed-doc` error. */
export const parseDocA = (raw: unknown): Result<DocA, DiscoveryError> => {
  const doc: Doc = 'A';
  if (!isRecord(raw)) {
    return Err(malformedDoc(doc, 'root is not an object'));
  }
  if (!isFiniteNumber(raw.version)) {
    return Err(malformedDoc(doc, 'version must be a finite number'));
  }
  if (!isFiniteNumber(raw.ttlSeconds)) {
    return Err(malformedDoc(doc, 'ttlSeconds must be a finite number'));
  }
  if (!isStringArray(raw.catalogHosts)) {
    return Err(malformedDoc(doc, 'catalogHosts must be a string array'));
  }
  if (raw.catalogHosts.length === 0) {
    return Err(malformedDoc(doc, 'catalogHosts must not be empty'));
  }
  return Ok(
    Object.freeze({
      version: raw.version,
      ttlSeconds: raw.ttlSeconds,
      catalogHosts: Object.freeze([...raw.catalogHosts]),
    }),
  );
};

const parseDocBLandscape = (raw: unknown): DocBLandscape | null => {
  if (!isRecord(raw)) {
    return null;
  }
  if (typeof raw.name !== 'string' || raw.name.length === 0) {
    return null;
  }
  if (typeof raw.displayName !== 'string') {
    return null;
  }
  if (!isStringRecord(raw.metadata)) {
    return null;
  }
  return Object.freeze({
    name: raw.name,
    displayName: raw.displayName,
    metadata: Object.freeze({ ...raw.metadata }),
  });
};

/** Parse Doc B from raw JSON. Returns a typed doc or a `malformed-doc` error. */
export const parseDocB = (raw: unknown): Result<DocB, DiscoveryError> => {
  const doc: Doc = 'B';
  if (!isRecord(raw)) {
    return Err(malformedDoc(doc, 'root is not an object'));
  }
  if (!isFiniteNumber(raw.version)) {
    return Err(malformedDoc(doc, 'version must be a finite number'));
  }
  if (typeof raw.platform !== 'string') {
    return Err(malformedDoc(doc, 'platform must be a string'));
  }
  if (typeof raw.env !== 'string') {
    return Err(malformedDoc(doc, 'env must be a string'));
  }
  if (!Array.isArray(raw.landscapes)) {
    return Err(malformedDoc(doc, 'landscapes must be an array'));
  }
  const landscapes: DocBLandscape[] = [];
  for (const entry of raw.landscapes) {
    const parsed = parseDocBLandscape(entry);
    if (parsed === null) {
      return Err(malformedDoc(doc, 'landscape entry is malformed'));
    }
    landscapes.push(parsed);
  }
  if (landscapes.length === 0) {
    return Err(malformedDoc(doc, 'landscapes must not be empty'));
  }
  return Ok(
    Object.freeze({
      version: raw.version,
      platform: raw.platform,
      env: raw.env,
      landscapes: Object.freeze(landscapes),
    }),
  );
};

const parseDocCList = (raw: unknown): DocCCandidateList | null => {
  if (!isRecord(raw)) {
    return null;
  }
  if (typeof raw.landscape !== 'string' || raw.landscape.length === 0) {
    return null;
  }
  if (typeof raw.service !== 'string' || raw.service.length === 0) {
    return null;
  }
  if (typeof raw.module !== 'string' || raw.module.length === 0) {
    return null;
  }
  if (!isStringArray(raw.candidates) || raw.candidates.length === 0) {
    return null;
  }
  return Object.freeze({
    landscape: raw.landscape,
    service: raw.service,
    module: raw.module,
    candidates: Object.freeze([...raw.candidates]),
  });
};

/** Parse Doc C from raw JSON. Returns a typed doc or a `malformed-doc` error. */
export const parseDocC = (raw: unknown): Result<DocC, DiscoveryError> => {
  const doc: Doc = 'C';
  if (!isRecord(raw)) {
    return Err(malformedDoc(doc, 'root is not an object'));
  }
  if (!isFiniteNumber(raw.version)) {
    return Err(malformedDoc(doc, 'version must be a finite number'));
  }
  if (typeof raw.platform !== 'string') {
    return Err(malformedDoc(doc, 'platform must be a string'));
  }
  if (typeof raw.env !== 'string') {
    return Err(malformedDoc(doc, 'env must be a string'));
  }
  if (!Array.isArray(raw.lists)) {
    return Err(malformedDoc(doc, 'lists must be an array'));
  }
  const lists: DocCCandidateList[] = [];
  for (const entry of raw.lists) {
    const parsed = parseDocCList(entry);
    if (parsed === null) {
      return Err(malformedDoc(doc, 'candidate list entry is malformed'));
    }
    lists.push(parsed);
  }
  if (lists.length === 0) {
    return Err(malformedDoc(doc, 'lists must not be empty'));
  }
  return Ok(
    Object.freeze({
      version: raw.version,
      platform: raw.platform,
      env: raw.env,
      lists: Object.freeze(lists),
    }),
  );
};
