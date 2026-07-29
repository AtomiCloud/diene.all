import { expectGreen } from './helpers.ts';

export async function packPackages(repo: any, label: string): Promise<void> {
  await expectGreen(
    repo,
    "nix develop .#ci -c bash -c './scripts/ci/setup.sh && find . -mindepth 2 -maxdepth 2 -type d \\( -name bin -o -name obj \\) -prune -exec rm -rf {} + && rm -rf artifacts/package && mkdir -p artifacts/package && dotnet pack dotnet-base.slnx -c Release --output artifacts/package'",
    label,
    600000,
  );
}
