{ pkgs, ... }:

{
  imports = [
    ./profiles/bat.nix
    ./profiles/direnv.nix
    ./profiles/fastfetch.nix
    ./profiles/fd.nix
    ./profiles/gh.nix
    ./profiles/git.nix
    ./profiles/helix.nix
    ./profiles/jq.nix
    ./profiles/ripgrep.nix
    ./profiles/tmux.nix
    ./profiles/tree.nix
    ./profiles/yt-dlp.nix
    ./profiles/zoxide.nix
    ./profiles/zsh
  ];

  catppuccin.enable = true;
  catppuccin.flavor = "mocha";

  home.packages = with pkgs; [
    cloudflared
    curl
    tokei
    tombi
    vscode-langservers-extracted
    wget
  ];
}
