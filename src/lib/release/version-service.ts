import type { RawCommit } from '../commits/model';
import { parseCommitMessage } from '../commits/parser';
import type { ReleaseLevel, ReleaserConfig } from '../config/model';

export interface SemVer {
  readonly major: number;
  readonly minor: number;
  readonly patch: number;
}

export interface ReleaseTag {
  readonly tag: string;
  readonly version: SemVer;
}

export interface VersionDecision {
  readonly level: Exclude<ReleaseLevel, false>;
  readonly version: SemVer;
}

const LEVEL_WEIGHT: Readonly<Record<Exclude<ReleaseLevel, false>, number>> = { patch: 1, minor: 2, major: 3 };

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function compareVersion(left: SemVer, right: SemVer): number {
  return left.major - right.major || left.minor - right.minor || left.patch - right.patch;
}

function maximumLevel(
  current: Exclude<ReleaseLevel, false> | null,
  candidate: ReleaseLevel,
): Exclude<ReleaseLevel, false> | null {
  if (candidate === false) return current;
  if (current === null || LEVEL_WEIGHT[candidate] > LEVEL_WEIGHT[current]) return candidate;
  return current;
}

function applyLevel(version: SemVer, level: Exclude<ReleaseLevel, false>): SemVer {
  if (level === 'major') return { major: version.major + 1, minor: 0, patch: 0 };
  if (level === 'minor') return { major: version.major, minor: version.minor + 1, patch: 0 };
  return { major: version.major, minor: version.minor, patch: version.patch + 1 };
}

export class VersionService {
  parseTag(tag: string, tagFormat: string): SemVer | null {
    const parts = tagFormat.split('${version}');
    if (parts.length !== 2) return null;
    const pattern = new RegExp(
      `^${escapeRegex(parts[0] ?? '')}(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)${escapeRegex(parts[1] ?? '')}$`,
    );
    const match = pattern.exec(tag);
    if (match === null) return null;
    return { major: Number(match[1]), minor: Number(match[2]), patch: Number(match[3]) };
  }

  latestTag(tags: readonly string[], tagFormat: string): ReleaseTag | null {
    let latest: ReleaseTag | null = null;
    for (const tag of tags) {
      const version = this.parseTag(tag, tagFormat);
      if (version !== null && (latest === null || compareVersion(version, latest.version) > 0))
        latest = { tag, version };
    }
    return latest;
  }

  analyze(config: ReleaserConfig, previous: SemVer | null, commits: readonly RawCommit[]): VersionDecision | null {
    let level: Exclude<ReleaseLevel, false> | null = null;
    for (const raw of commits) {
      const parsed = parseCommitMessage(raw.message, config.keywords);
      if (parsed.kind !== 'conventional') continue;
      const type = config.types.find(candidate => candidate.type === parsed.commit.type);
      if (type === undefined) continue;
      if (parsed.commit.breaking) {
        level = maximumLevel(level, 'major');
        continue;
      }
      if (parsed.commit.scope !== null && Object.hasOwn(config.specialScopes, parsed.commit.scope)) {
        level = maximumLevel(level, config.specialScopes[parsed.commit.scope]?.release ?? false);
        continue;
      }
      const scope = parsed.commit.scope ?? 'default';
      level = maximumLevel(level, type.scopes[scope]?.release ?? false);
    }
    if (level === null) return null;
    return {
      level,
      version: previous === null ? { major: 1, minor: 0, patch: 0 } : applyLevel(previous, level),
    };
  }

  format(version: SemVer): string {
    return `${version.major}.${version.minor}.${version.patch}`;
  }

  formatTag(tagFormat: string, version: SemVer): string {
    return tagFormat.replace('${version}', this.format(version));
  }
}
