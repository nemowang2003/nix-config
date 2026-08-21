{pkgs, ...}: {
  my.lsp.servers.ty = {
    package = pkgs.ty;
    args = ["server"];
  };

  my.lsp.servers.ruff = {
    package = pkgs.ruff;
    args = ["server"];
  };

  my.languages.python = {
    extensions = [".py"];
    roots = ["pyproject.toml"];
    lsp = ["ty" "ruff"];
    formatter = {
      command = "sh";
      args = ["-c" "ruff check --fix-only - | ruff format -"];
    };
    helix.autoFormat = true;
  };

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
          ignore = ["E501"];
        };
      };
    };

    ty = {
      enable = true;
    };

    uv = {
      enable = true;
      settings = {
        python-downloads = "never";
        python-preference = "only-system";
      };
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
