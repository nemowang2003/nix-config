{pkgs, ...}:
pkgs.writers.writePython3Bin "codex-archive-backtrack" {} (builtins.readFile ./main.py)
