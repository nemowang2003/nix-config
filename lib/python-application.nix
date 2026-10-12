{lib}: {
  pkgs,
  pyproject-nix,
  root,
  python-packages ? pkgs.python314Packages,
  test-dependencies ? null,
}: let
  project = pyproject-nix.lib.project.loadPyproject {projectRoot = root;};
  project-attrs = project.renderers.buildPythonPackage {
    python = pkgs.python314;
    pythonPackages = python-packages;
  };
  scripts = project.pyproject.project.scripts;
  completions =
    lib.filter
    (name: builtins.pathExists (root + "/_${name}"))
    (lib.attrNames scripts);
  application = pkgs.python314Packages.buildPythonApplication (project-attrs
    // {
      nativeBuildInputs = (project-attrs.nativeBuildInputs or []) ++ lib.optionals (completions != []) [pkgs.installShellFiles];
      postInstall =
        (project-attrs.postInstall or "")
        + lib.concatMapStrings
        (name: "\ninstallShellCompletion --zsh ${lib.escapeShellArg "_${name}"}\n")
        completions;
      pythonImportsCheck = lib.unique (map
        (script: lib.head (lib.splitString ":" script))
        (lib.attrValues scripts));
      meta =
        (project-attrs.meta or {})
        // lib.optionalAttrs (builtins.length (lib.attrNames scripts) == 1) {
          mainProgram = lib.head (lib.attrNames scripts);
        };
      passthru.tests = lib.optionalAttrs (builtins.pathExists (root + "/tests")) {
        # Source tests stay independent of the application build. Packages can
        # omit heavyweight runtime dependencies when their tests mock them.
        unit = let
          test-python = pkgs.python314.withPackages (_:
            if test-dependencies == null
            then application.propagatedBuildInputs
            else test-dependencies);
        in
          pkgs.runCommand "${project.pyproject.project.name}-unit-tests" {} ''
            export PYTHONDONTWRITEBYTECODE=1
            cd ${root}
            export PYTHONPATH="$PWD/src"
            ${lib.getExe test-python} -m unittest discover -s tests
            touch "$out"
          '';
      };
    });
in
  application
