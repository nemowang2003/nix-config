{inputs, ...}: {
  perSystem = {
    pkgs,
    lib,
    system,
    ...
  }: let
    python-packages =
      lib.filterAttrs
      (name: kind: kind == "directory" && builtins.pathExists (../packages + "/${name}/pyproject.toml"))
      (builtins.readDir ../packages);
    config = inputs.nixago.lib.${system}.make {
      output = ".pre-commit-config.yaml";
      format = "yaml";
      hook.mode = "copy";
      data.repos = [
        {
          repo = "local";
          hooks = [
            {
              id = "alejandra";
              name = "alejandra";
              language = "system";
              entry = lib.getExe pkgs.alejandra;
              types = ["nix"];
            }
            {
              id = "ruff-check";
              name = "ruff-check";
              language = "system";
              entry = "${lib.getExe pkgs.ruff} check --fix";
              types = ["python"];
            }
            {
              id = "ruff-format";
              name = "ruff-format";
              language = "system";
              entry = "${lib.getExe pkgs.ruff} format";
              types = ["python"];
            }
          ];
        }
        {
          repo = "https://github.com/astral-sh/ty-pre-commit";
          rev = "v0.0.88";
          hooks = map (name: {
            id = "ty";
            alias = "ty-${name}";
            name = "ty (${name})";
            # These independent Nix packages have no uv lockfiles or environments.
            args = [
              "--isolated"
              "--project"
              "packages/${name}"
              "--python"
              (lib.getExe pkgs.python314)
            ];
          }) (lib.attrNames python-packages);
        }
      ];
    };
  in {
    devshells.default.packages = [pkgs.pre-commit];
    devshells.default.devshell.startup.pre-commit-config.text = config.shellHook;
  };
}
