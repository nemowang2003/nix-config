# Global Instructions

## Nix environment

This machine is managed with Nix. Prefer `nix run` and `nix shell` to obtain
tools and dependencies instead of installing them with system package
managers or other non-Nix means.

## Python dependencies

Use `uv` to manage Python dependencies (`uv add`, `uv sync`, `uv run`). Do not
use `pip install` or create virtual environments manually.

## Commit discipline

Commit early and often. After each coherent change, make a focused commit with
a concise scoped message rather than accumulating unrelated edits or leaving
work uncommitted for long stretches.
