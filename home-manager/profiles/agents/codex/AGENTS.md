# Global Instructions

## Nix environment

This machine is managed with Nix. Prefer `nix run` and `nix shell` to obtain
tools and dependencies instead of installing them with system package
managers or other non-Nix means.

## Python dependencies

Use `uv` to manage Python dependencies (`uv add`, `uv sync`, `uv run`). Do not
use `pip install` or create virtual environments manually.
