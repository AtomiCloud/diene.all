import { expect, test } from "bun:test";
import type { ProbeExecResult, ProbeRepo } from "@cyanprint/contracts";
import { expectSuccess } from "./exec";

test("failure output is redacted and bounded", async () => {
  const repo: ProbeRepo = {
    async exec(): Promise<ProbeExecResult> {
      return {
        exitCode: 1,
        stdout: `ghp_secret ${"x".repeat(5_000)}`,
        stderr: "token=abc",
      };
    },
    async read() {
      return "";
    },
    async write() {},
    async remove() {},
    async glob() {
      return [];
    },
    async patch() {},
  };
  await expect(expectSuccess(repo, "false")).rejects.toThrow(
    "[REDACTED_GITHUB_TOKEN]",
  );
  await expect(expectSuccess(repo, "false")).rejects.toThrow(
    "[REDACTED_SECRET]",
  );
});
