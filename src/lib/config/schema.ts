import { z } from 'zod';
import { ConfigError } from '../errors';
import type { ReleaserConfig } from './model';

const SKIP_CI = /\[(?:skip ci|ci skip)\]/i;
const NAME = /^[a-z][a-z0-9-]*$/;

const releaseLevel = z.union([z.literal('major'), z.literal('minor'), z.literal('patch'), z.literal(false)]);

const vae = z.strictObject({
  verb: z.string().min(1),
  application: z.string().min(1),
  example: z.string().min(1),
});

const scopeRule = z.strictObject({
  desc: z.string().min(1),
  release: releaseLevel,
});

const scopes = z
  .record(z.string().regex(NAME, 'scope names must be lower-case identifiers'), scopeRule)
  .refine(value => Object.hasOwn(value, 'default'), 'every type requires a `default` scope');

const commitType = z.strictObject({
  type: z.string().regex(NAME, 'type names must be lower-case identifiers'),
  desc: z.string().min(1),
  section: z.string().min(1).optional(),
  vae: vae.optional(),
  scopes,
});

const specialScope = z.strictObject({
  desc: z.string().min(1),
  release: releaseLevel,
});

const headerLint = z
  .strictObject({
    maxLength: z.number().int().positive().default(72),
    minLength: z.number().int().positive().default(5),
    forbiddenWords: z.array(z.string().min(1)).default(['WIP']),
    forbidTrailingPunctuation: z.boolean().default(true),
  })
  .refine(value => value.minLength <= value.maxLength, 'minLength must not exceed maxLength');

const bodyLint = z.strictObject({
  maxLineLength: z.number().int().positive().default(80),
  minLengthWhenPresent: z.number().int().nonnegative().default(20),
  requireBlankSecondLine: z.boolean().default(true),
});

const ignoredCommitKind = z.enum(['merge', 'revert', 'fixup', 'fixup-amend', 'squash']);

const lint = z.strictObject({
  header: headerLint.prefault({}),
  body: bodyLint.prefault({}),
  ignore: z.array(ignoredCommitKind).default(['merge', 'revert', 'fixup', 'fixup-amend', 'squash']),
});

const conventions = z.strictObject({
  path: z.string().min(1),
  template: z.string().min(1),
});

const changelog = z.strictObject({
  path: z.string().min(1),
  title: z.string().min(1).default('# Changelog'),
});

const prepareHook = z.strictObject({
  phase: z.enum(['beforeWrite', 'afterWrite']),
  command: z.string().min(1),
});

const hooks = z
  .strictObject({
    prepare: z.array(prepareHook).default([]),
    success: z.array(z.string().min(1)).default([]),
  })
  .prefault({});

const github = z.union([
  z.literal(false),
  z.strictObject({
    enabled: z.literal(true),
    successComment: z.string().min(1).default('Released in ${version}.'),
    releasedLabels: z.array(z.string().min(1)).default(['released']),
  }),
]);

const commit = z.strictObject({
  message: z
    .string()
    .min(1)
    .refine(value => !SKIP_CI.test(value), 'commit message must not contain a skip-CI token'),
  assets: z.array(z.string().min(1)).nonempty(),
});

const release = z.strictObject({
  branches: z.array(z.string().min(1)).nonempty(),
  tagFormat: z
    .string()
    .min(1)
    .default('v${version}')
    .refine(value => (value.match(/\$\{version\}/g) ?? []).length === 1, {
      message: 'tagFormat must contain exactly one ${version} placeholder',
    }),
  changelog,
  commit,
  github: github.default(false),
  hooks,
});

const canonicalV2 = z
  .strictObject({
    schemaVersion: z.literal(2),
    types: z.array(commitType).nonempty(),
    specialScopes: z.record(z.string().regex(NAME), specialScope).default({}),
    keywords: z.array(z.string().min(1)).default(['BREAKING CHANGE', 'BREAKING CHANGES', 'BREAKING']),
    lint: lint.prefault({}),
    conventions,
    release,
  })
  .superRefine((value, context) => {
    const typeNames = value.types.map(type => type.type);
    if (new Set(typeNames).size !== typeNames.length) {
      context.addIssue({ code: 'custom', path: ['types'], message: 'type names must be unique' });
    }
    if (new Set(value.release.branches).size !== value.release.branches.length) {
      context.addIssue({ code: 'custom', path: ['release', 'branches'], message: 'branches must be unique' });
    }
    if (new Set(value.release.commit.assets).size !== value.release.commit.assets.length) {
      context.addIssue({ code: 'custom', path: ['release', 'commit', 'assets'], message: 'assets must be unique' });
    }
    if (new Set(value.keywords).size !== value.keywords.length) {
      context.addIssue({ code: 'custom', path: ['keywords'], message: 'keywords must be unique' });
    }
  });

export function detectSchemaVersion(raw: unknown): 1 | 2 {
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new ConfigError('configuration must be a mapping');
  }
  const record = raw as Record<string, unknown>;
  if (record.schemaVersion === 2) return 2;
  if (record.schemaVersion !== undefined) {
    throw new ConfigError(`unsupported schemaVersion: ${JSON.stringify(record.schemaVersion)} (expected 2)`);
  }
  if ('plugins' in record || 'branches' in record) return 1;
  throw new ConfigError('unrecognized configuration: expected schemaVersion 2 or a legacy v1 document');
}

export function formatZodIssues(error: z.ZodError): string {
  return error.issues
    .map(issue => `${issue.path.length === 0 ? '<root>' : issue.path.join('.')}: ${issue.message}`)
    .join('; ');
}

export function parseCanonicalV2(raw: unknown): ReleaserConfig {
  const result = canonicalV2.safeParse(raw);
  if (!result.success) throw new ConfigError(`invalid v2 configuration: ${formatZodIssues(result.error)}`);
  return result.data as ReleaserConfig;
}
