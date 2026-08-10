{
  pkgs,
  packages,
  env,
  shellHook,
}:
with env;
{
  cd = pkgs.mkShell {
    buildInputs = main ++ system;
    inherit shellHook;
  };

  ci = pkgs.mkShell {
    buildInputs = lint ++ main ++ system;
    inherit shellHook;

    # ### nextjs-frontend-playwright-env-ci
    # #### source: nextjs-frontend
    PLAYWRIGHT_BROWSERS_PATH = packages.playwright-browsers;
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
  };

  default = pkgs.mkShell {
    buildInputs = system ++ main ++ lint ++ dev;
    inherit shellHook;

    # ### nextjs-frontend-playwright-env-default
    # #### source: nextjs-frontend
    PLAYWRIGHT_BROWSERS_PATH = packages.playwright-browsers;
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
  };

  releaser = pkgs.mkShell {
    buildInputs = lint ++ main ++ releaser ++ system;
    inherit shellHook;
  };
}
