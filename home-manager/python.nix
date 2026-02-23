{ pkgs, ... }:

{
  imports = [
    ./profiles/ruff.nix
    ./profiles/ty.nix
    ./profiles/uv.nix
  ];

  home.packages = with pkgs; [
    python314
  ];
}
