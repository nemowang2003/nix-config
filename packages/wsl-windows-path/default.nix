{pkgs, ...}:
pkgs.writeShellScriptBin "wsl-windows-path" (builtins.readFile ./windows-path.sh)
