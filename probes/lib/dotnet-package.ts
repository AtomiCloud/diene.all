import { expectGreen } from './helpers.ts';

export async function packPackages(repo: any, label: string): Promise<void> {
  await expectGreen(
    repo,
    "nix develop .#ci -c bash -c './scripts/ci/setup.sh && rm -rf artifacts/package && mkdir -p artifacts/package && dotnet pack dotnet-base.slnx -c Release --output artifacts/package'",
    label,
    600000,
  );
}
