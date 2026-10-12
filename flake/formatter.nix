{inputs, ...}: let
  ruff-settings = {
    line-length = 100;
    lint = {
      select = ["E" "W" "F" "I"];
      ignore = ["E501"];
    };
  };
in {
  flake.formatter-settings.ruff = ruff-settings;

  perSystem = {
    pkgs,
    system,
    ...
  }: let
    ruff-config = inputs.nixago.lib.${system}.make {
      output = "ruff.toml";
      format = "toml";
      data = ruff-settings;
      hook.mode = "copy";
    };
    python-format = pkgs.writeShellApplication {
      name = "python-format";
      runtimeInputs = [pkgs.ruff];
      text = ''
        ruff check --fix-only "$@"
        ruff format "$@"
      '';
    };
    treefmt-config = (pkgs.formats.toml {}).generate "treefmt.toml" {
      formatter = {
        nix = {
          command = "${pkgs.alejandra}/bin/alejandra";
          includes = ["*.nix"];
        };
        python = {
          command = "${python-format}/bin/python-format";
          includes = ["*.py"];
        };
      };
    };
  in {
    devshells.default.devshell.startup.ruff-config.text = ruff-config.shellHook;

    formatter = pkgs.writeShellApplication {
      name = "repo-format";
      runtimeInputs = [pkgs.treefmt];
      text = ''
        exec treefmt --config-file ${treefmt-config} --tree-root "$PWD" "$@"
      '';
    };
  };
}
