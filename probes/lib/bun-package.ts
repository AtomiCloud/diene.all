import { expectBunGreen } from './bun-command.ts';

export async function packBunLibrary(repo: any, label: string): Promise<void> {
  await expectBunGreen(
    repo,
    "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && ./scripts/local/build.sh && rm -f pkg.tgz && bun pm pack --filename pkg.tgz'",
    label,
  );
}
