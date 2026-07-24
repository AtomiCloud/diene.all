import type { CommitType, ReleaseLevel, ReleaserConfig } from '../config/model';
import { ConfigError } from '../errors';

const MARKERS = ['CONVENTION_DOCS_PLACEHOLDER', 'var___convention_docs___'] as const;

function releaseName(level: ReleaseLevel): string {
  return level === false ? 'no release' : level;
}

function escapeCell(value: string): string {
  return value.replaceAll('|', '\\|').replaceAll('\n', '<br>');
}

function typeRelease(type: CommitType): string {
  const releases = new Set(Object.values(type.scopes).map(scope => releaseName(scope.release)));
  return releases.size === 1 ? ([...releases][0] ?? 'no release') : 'scope-dependent';
}

function renderTypes(config: ReleaserConfig): string {
  const rows = config.types.map(type => `| \`${type.type}\` | ${escapeCell(type.desc)} | ${typeRelease(type)} |`);
  return ['## Types', '', '| Type | Description | Release |', '| --- | --- | --- |', ...rows].join('\n');
}

function renderScopes(config: ReleaserConfig): string {
  const blocks = config.types.map(type => {
    const rows = Object.entries(type.scopes).map(
      ([name, scope]) => `| \`${name}\` | ${escapeCell(scope.desc)} | ${releaseName(scope.release)} |`,
    );
    return [
      `### \`${type.type}\` scopes`,
      '',
      '| Scope | Description | Release |',
      '| --- | --- | --- |',
      ...rows,
    ].join('\n');
  });
  return ['## Scopes', '', ...blocks].join('\n\n');
}

function renderSpecialScopes(config: ReleaserConfig): string {
  const rows = Object.entries(config.specialScopes).map(
    ([name, scope]) => `| \`${name}\` | ${escapeCell(scope.desc)} | ${releaseName(scope.release)} |`,
  );
  if (rows.length === 0) return '## Special scopes\n\nNo special scopes are configured.';
  return ['## Special scopes', '', '| Scope | Description | Release |', '| --- | --- | --- |', ...rows].join('\n');
}

function renderVae(config: ReleaserConfig): string {
  const rows = config.types
    .filter(type => type.vae !== undefined)
    .map(
      type =>
        `| \`${type.type}\` | ${escapeCell(type.vae?.verb ?? '')} | ${escapeCell(type.vae?.application ?? '')} | \`${escapeCell(type.vae?.example ?? '')}\` |`,
    );
  if (rows.length === 0) return '## V.A.E. guidance\n\nNo V.A.E. guidance is configured.';
  return [
    '## V.A.E. guidance',
    '',
    '| Type | Verb | Application | Example |',
    '| --- | --- | --- | --- |',
    ...rows,
  ].join('\n');
}

export class ConventionsService {
  render(config: ReleaserConfig): string {
    const marker = MARKERS.find(candidate => config.conventions.template.includes(candidate));
    if (marker === undefined) {
      throw new ConfigError(`conventions template must contain ${MARKERS.join(' or ')}`);
    }
    const generated = [
      "Use `type(scope)!: subject`. Omit `(scope)` only when the type's `default` scope applies.",
      '',
      renderTypes(config),
      renderScopes(config),
      renderSpecialScopes(config),
      renderVae(config),
    ].join('\n\n');
    return `${config.conventions.template.replace(marker, generated).trimEnd()}\n`;
  }
}
