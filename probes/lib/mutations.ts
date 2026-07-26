import type { ProbeRepo } from "@cyanprint/contracts";
import { expectSuccess, shellQuote } from "./exec";

type Replacement = {
  find: RegExp;
  replace: string | ((match: string, ...groups: string[]) => string);
};

type MutationResult = {
  path: string;
};

const TEST_GLOBS = [
  "tests/**/*.{test,spec}.{ts,tsx,js,jsx}",
  "tests/**/*.test.dart",
  "**/*.{test,spec}.{ts,tsx,js,jsx}",
  "**/*_test.dart",
  "**/*Test*/**/*.cs",
  "**/*_test.go",
];

const ASSERTION_FLIPS: Replacement[] = [
  { find: /\.toBe\(true\)/, replace: ".toBe(false)" },
  { find: /\.toEqual\(true\)/, replace: ".toEqual(false)" },
  { find: /\.toBeTruthy\(\)/, replace: ".toBeFalsy()" },
  { find: /\.Should\(\)\.BeTrue\(\)/, replace: ".Should().BeFalse()" },
  { find: /\bAssert\.True\(/, replace: "Assert.False(" },
  { find: /\brequire\.True\(t,/, replace: "require.False(t," },
  { find: /\bassert\.True\(t,/, replace: "assert.False(t," },
  { find: /\bexpect\(([^\n]+),\s*isTrue\)/, replace: "expect($1, isFalse)" },
];

async function uniquePaths(
  repo: ProbeRepo,
  globs: string[],
): Promise<string[]> {
  const paths = new Set<string>();
  for (const glob of globs) {
    for (const path of await repo.glob(glob)) {
      paths.add(path);
    }
  }
  return [...paths].sort();
}

async function replaceFirst(
  repo: ProbeRepo,
  globs: string[],
  replacements: Replacement[],
  subject: string,
): Promise<MutationResult> {
  for (const path of await uniquePaths(repo, globs)) {
    const source = await repo.read(path);
    for (const replacement of replacements) {
      if (!replacement.find.test(source)) {
        continue;
      }
      replacement.find.lastIndex = 0;
      await repo.write(
        path,
        source.replace(replacement.find, replacement.replace as never),
      );
      return { path };
    }
  }
  throw new Error(`no structural target found for ${subject}`);
}

export async function flipAssertion(
  repo: ProbeRepo,
  options?: { globs?: string[]; replacements?: Replacement[] },
): Promise<MutationResult> {
  return replaceFirst(
    repo,
    options?.globs ?? TEST_GLOBS,
    options?.replacements ?? ASSERTION_FLIPS,
    "an assertion flip",
  );
}

export async function breakShellGuard(
  repo: ProbeRepo,
  options?: { globs?: string[] },
): Promise<MutationResult> {
  return replaceFirst(
    repo,
    options?.globs ?? ["scripts/**/*.sh"],
    [
      {
        find: /^(\s*\[[^\n]+\]\s*&&[^\n]*?)\bexit\s+1\b/m,
        replace: "$1exit 0",
      },
    ],
    "a shell guard",
  );
}

function namespaceFrom(source: string): string {
  return source.match(/\bnamespace\s+([A-Za-z0-9_.]+)/)?.[1] ?? "ProbeMutation";
}

function packageFrom(source: string): string {
  const packageName = source.match(/^package\s+([A-Za-z0-9_]+)/m)?.[1];
  if (!packageName) {
    throw new Error("could not infer Go package for uncovered domain file");
  }
  return packageName;
}

export async function uncoverDomainFile(
  repo: ProbeRepo,
  options?: { path?: string; content?: string },
): Promise<MutationResult> {
  if (options?.path && options.content) {
    await repo.write(options.path, options.content);
    return { path: options.path };
  }

  const TypeScript = await uniquePaths(repo, [
    "src/lib/**/*.{ts,tsx}",
    "src/domain/**/*.{ts,tsx}",
  ]);
  if (TypeScript.length > 0) {
    const path = options?.path ?? "src/lib/__probe_uncovered__.ts";
    await repo.write(
      path,
      options?.content ?? "export const probeUncovered = (): number => 1;\n",
    );
    return { path };
  }

  const csharp = await uniquePaths(repo, ["Lib/**/*.cs", "src/**/*.cs"]);
  if (csharp.length > 0) {
    const path =
      options?.path ??
      `${csharp[0].slice(0, csharp[0].lastIndexOf("/") + 1)}ProbeUncovered.cs`;
    const namespace = namespaceFrom(await repo.read(csharp[0]));
    await repo.write(
      path,
      options?.content ??
        `namespace ${namespace};\n\npublic static class ProbeUncovered\n{\n    public static int Value() => 1;\n}\n`,
    );
    return { path };
  }

  const go = (await uniquePaths(repo, ["**/*.go"])).filter(
    (path) => !path.endsWith("_test.go"),
  );
  if (go.length > 0) {
    const path =
      options?.path ??
      `${go[0].slice(0, go[0].lastIndexOf("/") + 1)}probe_uncovered.go`;
    const packageName = packageFrom(await repo.read(go[0]));
    await repo.write(
      path,
      options?.content ??
        `package ${packageName}\n\nfunc probeUncovered() int { return 1 }\n`,
    );
    return { path };
  }

  const dart = await uniquePaths(repo, ["lib/**/*.dart"]);
  if (dart.length > 0) {
    const path = options?.path ?? "lib/src/probe_uncovered.dart";
    await repo.write(path, options?.content ?? "int probeUncovered() => 1;\n");
    return { path };
  }

  throw new Error(
    "no structural domain source target found for an uncovered file",
  );
}

export async function plantSecret(
  repo: ProbeRepo,
  options?: { staged?: boolean; path?: string; value?: string },
): Promise<MutationResult> {
  const path = options?.path ?? "probe-secret.txt";
  const value = options?.value ?? "probe-fake-github-token-not-a-credential";
  await repo.write(path, `PROBE_FAKE_GITHUB_TOKEN=${value}\n`);
  if (options?.staged) {
    await expectSuccess(repo, `git add -- ${shellQuote(path)}`);
  }
  return { path };
}

export async function staleHelmDocs(
  repo: ProbeRepo,
  options?: { globs?: string[] },
): Promise<MutationResult> {
  const candidates = await uniquePaths(
    repo,
    options?.globs ?? [
      "infra/**/values.yaml",
      "charts/**/values.yaml",
      "values.yaml",
    ],
  );
  if (candidates.length === 0) {
    throw new Error("no Helm values file found for a stale helm-docs mutation");
  }
  const path = candidates[0];
  const source = await repo.read(path);
  await repo.write(
    path,
    `${source.trimEnd()}\n\n# -- Probe-only value that makes generated Helm docs stale.\nprobeHelmDocsStale: true\n`,
  );
  return { path };
}

export type FormatterKind =
  | "nixfmt"
  | "prettier-markdown"
  | "prettier-yaml"
  | "shfmt";

export async function unformatFile(
  repo: ProbeRepo,
  options: { formatter: FormatterKind; globs?: string[] },
): Promise<MutationResult> {
  switch (options.formatter) {
    case "nixfmt":
      return replaceFirst(
        repo,
        options.globs ?? ["**/*.nix"],
        [{ find: /\s=\s/, replace: "=" }],
        "a nixfmt violation",
      );
    case "prettier-markdown": {
      const candidates = await uniquePaths(repo, options.globs ?? ["**/*.md"]);
      if (candidates.length === 0) {
        throw new Error("no Markdown file found for a Prettier mutation");
      }
      const path = candidates[0];
      await repo.write(
        path,
        `${(await repo.read(path)).trimEnd()}\n\n-  probe    formatting\n`,
      );
      return { path };
    }
    case "prettier-yaml": {
      const candidates = await uniquePaths(
        repo,
        options.globs ?? ["**/*.{yaml,yml}"],
      );
      if (candidates.length === 0) {
        throw new Error("no YAML file found for a Prettier mutation");
      }
      const path = candidates[0];
      await repo.write(
        path,
        `${(await repo.read(path)).trimEnd()}\nprobe_formatter:    true\n`,
      );
      return { path };
    }
    case "shfmt": {
      const candidates = await uniquePaths(
        repo,
        options.globs ?? ["scripts/**/*.sh"],
      );
      if (candidates.length === 0) {
        throw new Error("no shell file found for a shfmt mutation");
      }
      const path = candidates[0];
      await repo.write(
        path,
        `${(await repo.read(path)).trimEnd()}\nif true;then\n echo probe\nfi\n`,
      );
      return { path };
    }
  }
}

export async function invalidWorkflow(
  repo: ProbeRepo,
  options?: { mode?: "syntax" | "missing-script"; globs?: string[] },
): Promise<MutationResult> {
  const globs = options?.globs ?? [".github/workflows/**/*.{yaml,yml}"];
  if (options?.mode === "missing-script") {
    return replaceFirst(
      repo,
      globs,
      [
        {
          find: /(?:\.\/)?scripts\/ci\/[A-Za-z0-9._/-]+\.sh/,
          replace: "scripts/ci/__probe_missing__.sh",
        },
      ],
      "a missing jobs-to-scripts target",
    );
  }
  return replaceFirst(
    repo,
    globs,
    [{ find: /^jobs:\s*$/m, replace: "jobs: [" }],
    "an invalid workflow",
  );
}
