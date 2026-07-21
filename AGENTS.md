# Repository Guidelines

## Project Structure & Module Organization

This repository is a Nix flake for personal machine configuration across macOS, NixOS, WSL, and generic Linux.

- `flake.nix` declares inputs and loads flake modules from `flake/`.
- `flake/hosts.nix` is the host registry. Add machines here before creating host modules.
- `flake/configurations.nix` builds `darwinConfigurations`, `nixosConfigurations`, and standalone `homeConfigurations`.
- `darwin/`, `nixos/`, and `home-manager/` contain shared modules and profiles.
- `hosts/<hostname>/{darwin,nixos,home-manager}/default.nix` contains per-host overrides.
- `secrets/env/` stores sops-managed encrypted environment secrets.
- `lib/` contains shared helper functions.

## Build, Test, and Development Commands

Use the devshell via direnv or `nix develop`.

- `hms`: run `home-manager switch --flake "$PRJ_ROOT"`.
- `rebuild`: run the host system rebuild, then `hms`; on generic Linux it only runs Home Manager.
- `update`: run `nix flake update`, then `rebuild`.
- `check-eval`: evaluate flake outputs for all hosts declared in `.#hosts`.
- `check-activation`: dry-run Home Manager activation packages for all hosts declared in `.#hosts`.
- `gh-keysync`: publish declared SSH public keys to GitHub.
- `sops-edit-env [hostname]`: edit common or host-specific encrypted environment secrets.

Useful low-level checks:

```bash
nix eval .#homeConfigurations."nemo@$(hostname -s)".config.home.stateVersion
nix eval .#user-pubkeys --json
```

## Coding Style & Naming Conventions

Write Nix with two-space indentation and prefer small, composable modules. Attribute names in new local metadata use kebab-case, such as `user-pubkeys`, `age-recipient`, and `build-nix-settings`. Keep host-independent logic in shared modules; keep host-specific choices under `hosts/<hostname>/`.

Format Nix files with Alejandra:

```bash
nix fmt
```

The flake formatter is Alejandra, so `nix fmt` is equivalent to formatting the repository with Alejandra.

## Testing Guidelines

There is no separate test suite. Validate by evaluating representative outputs before switching:

```bash
check-eval
```

For risky Home Manager changes, run `check-activation` before `hms` or `rebuild`. It can dry-run non-local architectures, but it only validates the activation package build plan; it does not prove the remote host can activate successfully.

## Commit & Pull Request Guidelines

Recent commits use concise scoped messages, often in Chinese, such as `home-manager: 加入 rust 相关工具` or `refactor: 重构 flake module 与 nix settings`. Use a short scope followed by the change. Mention affected hosts or modules when relevant. PRs should describe the configuration impact, list validation commands run, and call out secret, cache, or host-registry changes explicitly.

## Security & Configuration Tips

Do not commit decrypted secrets. Add new hosts with `age-recipient` before editing host secret files. Prefer system-level Nix substituter settings in `flake/nix-settings.nix`; avoid ad hoc user-level Nix cache configuration unless it is intentionally host-local.
