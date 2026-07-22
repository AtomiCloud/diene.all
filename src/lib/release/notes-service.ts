import type { RawCommit } from '../commits/model';
import { parseCommitMessage } from '../commits/parser';
import type { ReleaserConfig } from '../config/model';

export interface NotesRequest {
  readonly config: ReleaserConfig;
  readonly version: string;
  readonly previousTag: string | null;
  readonly newTag: string;
  readonly commits: readonly RawCommit[];
  readonly repositoryUrl: string | null;
  readonly date: string;
}

interface NoteEntry {
  readonly sha: string;
  readonly scope: string | null;
  readonly subject: string;
}

function compareEntries(left: NoteEntry, right: NoteEntry): number {
  return left.subject < right.subject
    ? -1
    : left.subject > right.subject
      ? 1
      : (left.scope ?? '') < (right.scope ?? '')
        ? -1
        : (left.scope ?? '') > (right.scope ?? '')
          ? 1
          : 0;
}

function renderEntry(entry: NoteEntry, repositoryUrl: string | null): string {
  const prefix = entry.scope === null ? '' : `**${entry.scope}:** `;
  const shortSha = entry.sha.slice(0, 7);
  const reference = repositoryUrl === null ? shortSha : `[${shortSha}](${repositoryUrl}/commit/${entry.sha})`;
  return `* ${prefix}${entry.subject} (${reference})`;
}

export class NotesService {
  render(request: NotesRequest): string {
    const heading =
      request.previousTag === null || request.repositoryUrl === null
        ? `## ${request.version} (${request.date})`
        : `## [${request.version}](${request.repositoryUrl}/compare/${request.previousTag}...${request.newTag}) (${request.date})`;
    const blocks: string[] = [heading];
    for (const type of request.config.types) {
      if (type.section === undefined) continue;
      const entries: NoteEntry[] = [];
      for (const raw of request.commits) {
        const parsed = parseCommitMessage(raw.message, request.config.keywords);
        if (parsed.kind === 'conventional' && parsed.commit.type === type.type) {
          entries.push({ sha: raw.sha, scope: parsed.commit.scope, subject: parsed.commit.subject });
        }
      }
      if (entries.length === 0) continue;
      entries.sort(compareEntries);
      blocks.push(
        `### ${type.section}\n\n${entries.map(entry => renderEntry(entry, request.repositoryUrl)).join('\n')}`,
      );
    }
    return `${blocks.join('\n\n\n')}\n`;
  }
}
