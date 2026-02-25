{ pkgs, lib, ... }:

{
  imports = [
    ./profiles/develop.nix
    # Broken
    # ./profiles/yt-dlp.nix
  ];
}
