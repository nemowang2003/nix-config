{lib}: {
  pkgs,
  uv2nix,
  pyproject-nix,
  pyproject-build-systems,
  root,
  name,
}: let
  workspace = uv2nix.lib.workspace.loadWorkspace {workspaceRoot = root;};
  python-set =
    (pkgs.callPackage pyproject-nix.build.packages {
      python = pkgs.python314;
    }).overrideScope (
      lib.composeManyExtensions [
        pyproject-build-systems.overlays.wheel
        (workspace.mkPyprojectOverlay {sourcePreference = "wheel";})
      ]
    );
  venv = python-set.mkVirtualEnv "${name}-env" workspace.deps.default;
  application = (pkgs.callPackages pyproject-nix.build.util {}).mkApplication {
    inherit venv;
    package = python-set.${name};
  };
in
  application.overrideAttrs (old: {
    passthru = (old.passthru or {}) // {inherit venv;};
  })
