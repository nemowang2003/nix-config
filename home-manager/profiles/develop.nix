{ pkgs, lib, ... }:

{
  config = lib.mkMerge [
    { programs.gh.enable = true; }

    # copilot
    {
      programs.helix.languages = {
        language-server.copilot = {
          command = "helix-assist";
          # TODO: sops
        };

        languages = [
          {
            name = "git-commit";
            language-servers = [ "copilot" ];
          }
        ];
      };
      # TODO: copilot install & config
    }
  
    # nix
    {
      home.packages = with pkgs; [
        alejandra
        nixd
      ];

      programs = {
        helix.languages.language = [
          {
            name = "nix";
            auto-format = true;
            formatter = {
              command = "alejandra";
            };
          }
        ];
      };
    }

    # python
    {
      programs = {
        ruff = {
          enable = true;
          settings = {
            line-length = 100;
            lint = {
              select = [
                "E" # pycodestyle errors
                "W" # pycodestyle warnings
                "F" # pyflakes
                "I" # isort
              ];
              ignore = [ "E501" ];
            };
          };
        };

        uv.enable = true;

        helix.languages.language = [
          {
            name = "python";
            auto-format = true;
            language-servers = [ "ruff" "helix-assist" ];
            roots = [ "pyproject.toml" ];
            formatter = {
              command = "sh";
              args = [ "-c" "ruff check --fix-only - | ruff format -" ];
            };
          }
        ];
      };

      home.shellAliases = {
        uv = "noglob uv";
        uva = "uv add";
        uvi = "uv init";
        uvl = "uv lock";
        uvlr = "uv lock --refresh";
        uvlu = "uv lock --upgrade";
        uvr = "uv run";
        uvs = "uv sync";
        uvsr = "uv sync --refresh";
        uvsu = "uv sync --upgrade";
      };
    }
  ];
}
