{
  pkgs,
  lib,
  ...
}: {
  programs = {
    mcp.servers.python-lsp = {
      type = "stdio";
      command = lib.getExe pkgs.ty;
      args = ["server"];
    };

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
          ignore = ["E501"];
        };
      };
    };

    uv = {
      enable = true;
      settings = {
        python-downloads = "never";
        python-preference = "only-system";
      };
    };

    helix.languages = {
      language-server = {
        ty = {
          command = lib.getExe pkgs.ty;
          args = ["server"];
        };
      };

      language = [
        {
          name = "python";
          auto-format = true;
          language-servers = ["ty" "ruff" "copilot"];
          roots = ["pyproject.toml"];
          formatter = {
            command = "sh";
            args = ["-c" "ruff check --fix-only - | ruff format -"];
          };
        }
      ];
    };
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
