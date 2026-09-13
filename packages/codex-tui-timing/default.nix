{pkgs, ...}: let
  python-src =
    builtins.replaceStrings
    ["@tmux@"]
    [(pkgs.lib.getExe pkgs.tmux)]
    (builtins.readFile ./codex-tui-timing.py);
in
  pkgs.writers.writePython3Bin "codex-tui-timing" {
    flakeIgnore = ["E501"];
  }
  python-src
