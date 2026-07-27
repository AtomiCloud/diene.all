{
  pkgs,
  packages,
  env,
  shellHook,
}:
with env;
{
  # ### workspace-cd
  # #### source: workspace
  cd = pkgs.mkShell {
    buildInputs = main ++ system;
    inherit shellHook;
  };

  # ### workspace-ci
  # #### source: workspace
  ci = pkgs.mkShell {
    buildInputs = lint ++ main ++ system;
    inherit shellHook;

    # ### nextjs-frontend-playwright-env-ci
    # #### source: nextjs-frontend
    PLAYWRIGHT_BROWSERS_PATH = packages.playwright-browsers;
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
  };

  # ### nix-root-default
  # #### source: main
  default = pkgs.mkShell {
    buildInputs = system ++ main ++ lint ++ dev;
    inherit shellHook;

    # ### nextjs-frontend-playwright-env-default
    # #### source: nextjs-frontend
    PLAYWRIGHT_BROWSERS_PATH = packages.playwright-browsers;
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
  };

  # ### workspace-releaser
  # #### source: workspace
  releaser = pkgs.mkShell {
    buildInputs = lint ++ main ++ releaser ++ system;
    inherit shellHook;
  };
}
