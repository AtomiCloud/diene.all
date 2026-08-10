{
  pkgs,
  packages,
  env,
  shellHook,
}:
with env;
{
  # `infralint` is the PROVIDER of skopeo, and `.#cd` is the one shell that needs it:
  # probes/docker-build.ts runs `nix develop .#cd -c skopeo inspect` on the OCI archive.
  # `cd` is `main ++ system`, neither of which carries `lint`, so without this the
  # binary is absent here while present in default/ci/releaser — which is why a
  # toolchain check scoped to `default` cannot answer for `cd`.
  #
  # NOT a bare `skopeo`: measured, `buildEnv [ infralint, skopeo ]` fails rc=1 with a
  # conflicting subpath, and default/ci/releaser all carry lint -> infralint, so a bare
  # package would collide in three of four shells.
  # NOT the whole `lint` group: `cd` is the deploy shell for every image and chart job,
  # and lint carries actionlint/pre-commit/treefmt/golangci-lint/staticcheck.
  cd = pkgs.mkShell {
    buildInputs = main ++ system ++ [ packages.infralint ];
    inherit shellHook;
  };

  ci = pkgs.mkShell {
    buildInputs = lint ++ main ++ system;
    inherit shellHook;
  };

  default = pkgs.mkShell {
    buildInputs = system ++ main ++ lint ++ dev;
    inherit shellHook;
  };

  releaser = pkgs.mkShell {
    buildInputs = lint ++ main ++ releaser ++ system;
    inherit shellHook;
  };
}
