{
  self,
  inputs,
  ...
}: {
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
    type-check = pkgs.writeShellApplication {
      name = "repo-type-check";
      text = lib.concatMapStringsSep "\n" (name: let
        application = self.packages.${system}.${name};
        python = pkgs.python314.withPackages (_: application.propagatedBuildInputs);
      in ''
        ${lib.getExe pkgs.ty} check --project packages/${name} --python ${lib.getExe python}
      '') (lib.attrNames python-packages);
    };
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
            {
              id = "ty";
              name = "ty";
              language = "system";
              entry = lib.getExe type-check;
              types = ["python"];
              pass_filenames = false;
            }
          ];
        }
      ];
    };
  in {
    devshells.default.packages = [pkgs.pre-commit];
    devshells.default.devshell.startup.pre-commit-config.text = config.shellHook;
  };
}
