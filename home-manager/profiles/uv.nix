{ pkgs, ... }:

{
  programs.uv = {
    enable = true;
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
