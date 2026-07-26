import { expect, test } from "bun:test";
import type { ProbeExecResult, ProbeRepo } from "@cyanprint/contracts";
import { expectSuccess, MAX_FAILURE_OUTPUT } from "./exec";

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
  const error = await expectSuccess(repo, "false").catch(
    (reason: unknown) => reason,
  );
  expect(error).toBeInstanceOf(Error);

  const message = (error as Error).message;
  expect(message).toContain("[REDACTED_GITHUB_TOKEN]");
  expect(message).toContain("[REDACTED_SECRET]");
  expect(message).toContain("…[truncated]");
  expect(message).not.toContain("x".repeat(5_000));
  expect(message.length).toBeLessThanOrEqual(
    "command failed (1): false\nstdout:\n".length +
      MAX_FAILURE_OUTPUT +
      "\n…[truncated]\nstderr:\n[REDACTED_SECRET]".length,
  );
});
