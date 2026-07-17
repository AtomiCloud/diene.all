import { describe, expect, test } from "bun:test";
import type { ProbeExecResult, ProbeRepo } from "@cyanprint/contracts";
import {
  breakShellGuard,
  flipAssertion,
  invalidWorkflow,
  plantSecret,
  staleHelmDocs,
  uncoverDomainFile,
  unformatFile,
} from "./mutations";

class FakeRepo implements ProbeRepo {
  readonly files = new Map<string, string>();
  readonly commands: string[] = [];

  constructor(files: Record<string, string>) {
    for (const [path, content] of Object.entries(files)) {
      this.files.set(path, content);
    }
  }

  async exec(command: string): Promise<ProbeExecResult> {
    this.commands.push(command);
    return { exitCode: 0, stdout: "", stderr: "" };
  }

  async read(path: string): Promise<string> {
    const content = this.files.get(path);
    if (content === undefined) {
      throw new Error(`missing fake file: ${path}`);
    }
    return content;
  }

  async write(path: string, content: string): Promise<void> {
    this.files.set(path, content);
  }

  async remove(path: string): Promise<void> {
    this.files.delete(path);
  }

  async glob(pattern: string): Promise<string[]> {
    const suffixes = [...pattern.matchAll(/\.([A-Za-z0-9]+)(?=[,}])/g)].map(
      (match) => `.${match[1]}`,
    );
    const simpleSuffix = pattern.match(/\*\.([A-Za-z0-9]+)$/)?.[1];
    const allowed = simpleSuffix ? [`.${simpleSuffix}`] : suffixes;
    return [...this.files.keys()].filter((path) => {
      if (
        pattern.startsWith(".github/workflows/") &&
        !path.startsWith(".github/workflows/")
      ) {
        return false;
      }
      if (pattern.startsWith("scripts/") && !path.startsWith("scripts/")) {
        return false;
      }
      if (pattern.startsWith("infra/") && !path.startsWith("infra/")) {
        return false;
      }
      return (
        allowed.length === 0 || allowed.some((suffix) => path.endsWith(suffix))
      );
    });
  }

  async patch(
    path: string,
    edit: { find: string; replace: string },
  ): Promise<void> {
    const source = await this.read(path);
    if (!source.includes(edit.find)) {
      throw new Error(`missing patch target: ${edit.find}`);
    }
    this.files.set(path, source.replace(edit.find, edit.replace));
  }
}

describe("structural probe mutators", () => {
  test("flips a test assertion without naming a sample file", async () => {
    const repo = new FakeRepo({
      "tests/unit/domain.test.ts": "expect(value).toBe(true);\n",
    });
    await flipAssertion(repo);
    expect(await repo.read("tests/unit/domain.test.ts")).toContain(
      ".toBe(false)",
    );
  });

  test("breaks a one-line shell guard", async () => {
    const repo = new FakeRepo({
      "scripts/local/secrets.sh":
        '[ -z "${TOKEN:-}" ] && echo missing >&2 && exit 1\n',
    });
    await breakShellGuard(repo);
    expect(await repo.read("scripts/local/secrets.sh")).toContain("exit 0");
  });

  test("creates an uncovered TypeScript domain file", async () => {
    const repo = new FakeRepo({
      "src/lib/service.ts": "export const service = 1;\n",
    });
    const result = await uncoverDomainFile(repo);
    expect(result.path).toBe("src/lib/__probe_uncovered__.ts");
    expect(repo.files.has(result.path)).toBeTrue();
  });

  test("plants and stages a fake secret", async () => {
    const repo = new FakeRepo({});
    const result = await plantSecret(repo, { staged: true });
    expect(await repo.read(result.path)).toContain("PROBE_FAKE_GITHUB_TOKEN");
    expect(repo.commands).toEqual(["git add -- 'probe-secret.txt'"]);
  });

  test("makes helm-docs stale by adding a documented value", async () => {
    const repo = new FakeRepo({
      "infra/root_chart/values.yaml": "service: app\n",
    });
    await staleHelmDocs(repo);
    expect(await repo.read("infra/root_chart/values.yaml")).toContain(
      "probeHelmDocsStale",
    );
  });

  test("creates formatter-specific violations", async () => {
    const repo = new FakeRepo({ "nix/packages.nix": "value = true;\n" });
    await unformatFile(repo, { formatter: "nixfmt" });
    expect(await repo.read("nix/packages.nix")).toContain("value=true");
  });

  test("breaks workflow syntax or jobs-to-scripts wiring independently", async () => {
    const syntaxRepo = new FakeRepo({
      ".github/workflows/ci.yaml": "jobs:\n  ci:\n",
    });
    await invalidWorkflow(syntaxRepo);
    expect(await syntaxRepo.read(".github/workflows/ci.yaml")).toContain(
      "jobs: [",
    );

    const wiringRepo = new FakeRepo({
      ".github/workflows/ci.yaml": "run: ./scripts/ci/test.sh\n",
    });
    await invalidWorkflow(wiringRepo, { mode: "missing-script" });
    expect(await wiringRepo.read(".github/workflows/ci.yaml")).toContain(
      "__probe_missing__.sh",
    );
  });
});
