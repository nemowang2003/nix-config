{pkgs, ...}: let
  lib = pkgs.lib;
  python-src =
    builtins.replaceStrings
    ["@fzf@"]
    [(lib.getExe pkgs.fzf)]
    (builtins.readFile ./main.py);
in
  pkgs.writers.writePython3Bin "codex-notify" {
    libraries = [pkgs.python3Packages.httpx];
    flakeIgnore = ["E501"];
  }
  python-src
