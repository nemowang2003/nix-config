{pkgs, ...}: let
  lib = pkgs.lib;
  python-src = builtins.readFile ./codex-reply.py;
in
  pkgs.writers.writePython3Bin "codex-reply" {
    libraries = [pkgs.python3Packages.websockets];
    flakeIgnore = ["E501"];
  }
  python-src
