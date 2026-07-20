import type { ProbeRepo } from "@cyanprint/contracts";
import { expectDevShellSuccess } from "./exec";

export type BinarySmokeCase = {
  name: string;
  versionOrHelp: string;
  operation: string;
};

export async function runBinarySmoke(
  repo: ProbeRepo,
  cases: BinarySmokeCase[],
  shell = "ci",
): Promise<void> {
  if (cases.length === 0) {
    throw new Error("binary smoke inventory is empty");
  }

  const seen = new Set<string>();
  for (const item of cases) {
    if (seen.has(item.name)) {
      throw new Error(
        `binary smoke inventory contains duplicate entry: ${item.name}`,
      );
    }
    seen.add(item.name);

    try {
      await expectDevShellSuccess(
        repo,
        `${item.versionOrHelp} && ${item.operation}`,
        shell,
      );
    } catch (error) {
      throw new Error(
        `binary smoke failed for ${item.name}: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }
}
