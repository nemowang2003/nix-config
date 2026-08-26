{pkgs, ...}: let
  lib = pkgs.lib;
  python-src =
    builtins.replaceStrings
    ["@curl@" "@fzf@"]
    [(lib.getExe pkgs.curl) (lib.getExe pkgs.fzf)]
    (builtins.readFile ./codex-notify.py);
in
  pkgs.writers.writePython3Bin "codex-notify" {flakeIgnore = ["E501"];} python-src
