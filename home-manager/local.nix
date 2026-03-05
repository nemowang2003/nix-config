{
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./profiles/develop.nix
    ./profiles/yt-dlp.nix
  ];
}
