{ pkgs, lib, ... }:

{
  imports = [
    ./profiles/git.nix
    ./profiles/helix.nix
    ./profiles/yt-dlp.nix
    ./profiles/zsh/default.nix
  ];

  catppuccin.enable = true;
  catppuccin.flavor = "mocha";

  home.packages = with pkgs; [
    bat
    bat-extras.batman
    cloudflared
    curl
    fastfetch
    fd
    gh
    home-manager
    jq
    (lib.lowPrio python313)
    python314
    ripgrep
    ruff
    tmux
    tokei
    tombi
    ty
    tree
    uv
    vscode-langservers-extracted
    wget
  ];
}
