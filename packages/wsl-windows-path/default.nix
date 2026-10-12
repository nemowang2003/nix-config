{pkgs, ...}:
pkgs.writeShellScriptBin "wsl-windows-path" (builtins.readFile ./main.sh)
