# Global Instructions

## Nix environment

This machine is managed with Nix. Prefer `nix run` and `nix shell` to obtain
tools and dependencies instead of installing them with system package
managers or other non-Nix means.

## Python dependencies

Use `uv` to manage Python dependencies (`uv add`, `uv sync`, `uv run`). Do not
use `pip install` or create virtual environments manually.

## Commit discipline

Commit coherent steps early while working. For larger work, start a development
branch with `git switch -c <branch-name>`, make focused commits there, then
squash or fixup related commits and rebase before integrating into `main`.
Keep `main` focused on one commit per logical change.
