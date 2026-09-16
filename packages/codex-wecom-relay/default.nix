{pkgs, ...}: let
  python-src = builtins.readFile ./main.py;
in
  pkgs.writers.writePython3Bin "codex-wecom-relay" {
    libraries = [pkgs.python3Packages.websockets];
    flakeIgnore = ["E501"];
  }
  python-src
