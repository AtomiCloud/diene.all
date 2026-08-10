import { z } from 'zod';
import { ConfigError, UnsupportedModuleError } from '../errors';
import type { PrepareHook, ReleaserConfig } from './model';
import { formatZodIssues, parseCanonicalV2 } from './schema';

const SKIP_CI_TOKEN = /[ \t]*\[(?:skip ci|ci skip)\][ \t]*/gi;

const legacyPlugin = z.strictObject({
  module: z.string().min(1),
  version: z.union([z.string(), z.number()]).optional(),
  config: z.record(z.string(), z.unknown()).optional(),
});

const legacyRoot = z.strictObject({
  conventionMarkdown: z.strictObject({ path: z.string().min(1), template: z.string().min(1) }),
  gitlint: z.string().min(1).optional(),
  keywords: z.array(z.string().min(1)).optional(),
  branches: z.array(z.string().min(1)).nonempty(),
  specialScopes: z.record(z.string(), z.unknown()).optional(),
  plugins: z.array(legacyPlugin),
  types: z.array(z.unknown()).nonempty(),
});

export interface TranslationResult {
  readonly config: ReleaserConfig;
  readonly warnings: readonly string[];
  readonly gitlintPath: string;
}

function normalizePlaceholders(value: string): string {
  return value.replaceAll('${nextRelease.version}', '${version}').replaceAll('${nextRelease.notes}', '${notes}');
}

function assertAllowedKeys(config: Record<string, unknown>, allowed: readonly string[], module: string): void {
  const unexpected = Object.keys(config).filter(key => !allowed.includes(key));
  if (unexpected.length > 0) {
    throw new UnsupportedModuleError(
      `${module} lifecycle/config key "${unexpected[0]}" is unsupported; move it to release.hooks.prepare/success`,
    );
  }
}

function optionalString(config: Record<string, unknown>, key: string, module: string): string | undefined {
  const value = config[key];
  if (value === undefined) return undefined;
  if (typeof value !== 'string') throw new ConfigError(`${module}.${key} must be a string`);
  return value;
}

export function translateV1(raw: unknown): TranslationResult {
  const parsed = legacyRoot.safeParse(raw);
  if (!parsed.success) throw new ConfigError(`invalid v1 configuration: ${formatZodIssues(parsed.error)}`);
  const legacy = parsed.data;
  const warnings: string[] = [];
  const prepare: PrepareHook[] = [];
  const success: string[] = [];
  let changelogPath = 'Changelog.md';
  let changelogTitle = '# Changelog';
  let commitMessage: string | undefined;
  let commitAssets: string[] | undefined;
  let github: ReleaserConfig['release']['github'] = false;
  let seenChangelog = false;
  let seenGit = false;
  let seenGithub = false;

  for (const plugin of legacy.plugins) {
    const config = plugin.config ?? {};
    switch (plugin.module) {
      case '@semantic-release/changelog': {
        if (seenChangelog) throw new ConfigError('duplicate @semantic-release/changelog module');
        seenChangelog = true;
        assertAllowedKeys(config, ['changelogFile', 'changelogTitle'], plugin.module);
        changelogPath = optionalString(config, 'changelogFile', plugin.module) ?? changelogPath;
        changelogTitle = optionalString(config, 'changelogTitle', plugin.module) ?? changelogTitle;
        break;
      }
      case '@semantic-release/exec': {
        assertAllowedKeys(config, ['prepareCmd', 'successCmd'], plugin.module);
        const prepareCmd = optionalString(config, 'prepareCmd', plugin.module);
        const successCmd = optionalString(config, 'successCmd', plugin.module);
        if (prepareCmd !== undefined) {
          prepare.push({
            phase: seenChangelog ? 'afterWrite' : 'beforeWrite',
            command: normalizePlaceholders(prepareCmd),
          });
        }
        if (successCmd !== undefined) success.push(normalizePlaceholders(successCmd));
        break;
      }
      case '@semantic-release/git': {
        if (seenGit) throw new ConfigError('duplicate @semantic-release/git module');
        seenGit = true;
        assertAllowedKeys(config, ['message', 'assets'], plugin.module);
        const message = optionalString(config, 'message', plugin.module);
        if (message === undefined) throw new ConfigError('@semantic-release/git requires a string `message`');
        const assets = config.assets;
        if (!Array.isArray(assets) || !assets.every(asset => typeof asset === 'string')) {
          throw new ConfigError('@semantic-release/git requires a string[] `assets`');
        }
        const normalized = normalizePlaceholders(message);
        commitMessage = normalized.replace(SKIP_CI_TOKEN, '');
        commitAssets = assets;
        if (commitMessage !== normalized)
          warnings.push('removed legacy [skip ci] token from the release commit message');
        break;
      }
      case '@semantic-release/github': {
        if (seenGithub) throw new ConfigError('duplicate @semantic-release/github module');
        seenGithub = true;
        assertAllowedKeys(config, ['successComment', 'releasedLabels'], plugin.module);
        const releasedLabels = config.releasedLabels;
        if (
          releasedLabels !== undefined &&
          (!Array.isArray(releasedLabels) ||
            !releasedLabels.every(label => typeof label === 'string' && label.length > 0))
        ) {
          throw new ConfigError('@semantic-release/github.releasedLabels must be a string[]');
        }
        github = {
          enabled: true,
          successComment: normalizePlaceholders(
            optionalString(config, 'successComment', plugin.module) ?? 'Released in ${version}.',
          ),
          releasedLabels: releasedLabels === undefined ? ['released'] : (releasedLabels as string[]),
        };
        break;
      }
      default:
        throw new UnsupportedModuleError(
          `unsupported module "${plugin.module}"; only changelog/exec/git/github translate — move the rest to release.hooks.prepare/success`,
        );
    }
  }

  if (!seenChangelog) throw new ConfigError('v1 configuration requires an @semantic-release/changelog module');
  if (commitMessage === undefined || commitAssets === undefined) {
    throw new ConfigError('v1 configuration requires an @semantic-release/git module');
  }

  const canonical = {
    schemaVersion: 2,
    types: legacy.types,
    ...(legacy.specialScopes === undefined ? {} : { specialScopes: legacy.specialScopes }),
    ...(legacy.keywords === undefined ? {} : { keywords: legacy.keywords }),
    conventions: legacy.conventionMarkdown,
    release: {
      branches: legacy.branches,
      changelog: { path: changelogPath, title: changelogTitle },
      commit: { message: commitMessage, assets: commitAssets },
      github,
      hooks: { prepare, success },
    },
  };

  return {
    config: parseCanonicalV2(canonical),
    warnings,
    gitlintPath: legacy.gitlint ?? '.gitlint',
  };
}
