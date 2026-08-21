# Repository Guidelines

## Project Structure & Module Organization

This repository is a Nix flake for personal machine configuration across macOS, NixOS, WSL, and generic Linux.

- `flake.nix` declares inputs and loads flake modules from `flake/`.
- `flake/hosts.nix` is the host registry. Add machines here before creating host modules.
- `flake/configurations.nix` builds `darwinConfigurations`, `nixosConfigurations`, and `genericConfigurations` for generic Linux hosts, plus standalone `homeConfigurations` for every host.
- `darwin/`, `nixos/`, `generic/`, and `home-manager/` contain shared modules and profiles.
- `generic/modules/` declares generic system options and builds the nix.conf/activation package; `generic/profiles/` provides the default generic Linux configuration; `hosts/<hostname>/generic/` overrides it per host.
- `packages/` is loaded in `flake/packages.nix` via `inputs.haumea.lib.load`, with `loader = loaders.callPackage` and `transformer = self.lib.haumea.force-shallow-transformer` (defined in `lib/haumea.nix`): a directory with `default.nix` exports `default` as the package (other files are loaded but not exported); a directory without `default.nix` is rejected.
- `home-manager/modules/` declares private Home Manager options and shared glue, such as `my.*`.
- `home-manager/profiles/` contains concrete program, language, and secret profiles.
- `hosts/<hostname>/{darwin,nixos,generic,home-manager}/default.nix` contains per-host overrides.
- `secrets/env/` stores sops-managed encrypted environment secrets.
- `lib/` contains shared helper functions.

## Build, Test, and Development Commands

Use the devshell via direnv or `nix develop`.

- `hms`: run `home-manager switch --flake "$PRJ_ROOT"`.
- `rebuild`: run the host system activation, then `hms`; on generic Linux it installs the system Nix configuration first.
- `nix run .#generic-rebuild [build|switch] [--flake <flake>]`: build or activate the current host's `genericConfigurations.<host>.config.system.build.activationPackage`; it resolves the host from `hostname -s`, and `switch` must run as root (the `rebuild` devshell command calls it on generic Linux).
- `update`: run `nix flake update`, then `rebuild`.
- `check-eval`: evaluate flake outputs for all hosts declared in `.#hosts`.
- `check-activation`: dry-run Home Manager activation packages for all hosts declared in `.#hosts`.
- `gh-keysync`: publish declared SSH public keys to GitHub.
- `sops-edit-env [common|trusted|hostname]`: edit common, trusted, or host-specific encrypted environment secrets.

Useful low-level checks:

```bash
nix eval .#homeConfigurations."nemo@$(hostname -s)".config.home.stateVersion
nix eval .#user-pubkeys --json
```

## Coding Style & Naming Conventions

Write Nix with two-space indentation and prefer small, composable modules. Attribute names in new local metadata use kebab-case, such as `user-pubkeys`, `age-recipient`, and `build-nix-settings`. Keep host-independent logic in shared modules; keep host-specific choices under `hosts/<hostname>/`.

Prefer kebab-case for local Nix variable and helper-function names as well (`agent-languages`, `notify-server-chan`). Short, conventional helpers such as `isDarwin`, `mkHost`, and upstream library functions like `mkOption` may remain camelCase; do not rename upstream option attributes or framework-provided arguments.

Use `my.*` for private cross-module metadata that is not part of Home Manager's upstream option namespace. Current private registries include `my.lsp.servers` for reusable LSP server commands, `my.languages` for language-level LSP and formatter declarations, `my.codex` for mutable Codex configuration, `my.skland` for Skland auto-sign wiring, and `my.env-secrets` for environment secrets materialized by the shared sops profile.

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

For risky Home Manager changes, run `check-activation` before `hms` or `rebuild`. It can dry-run non-local architectures, but it only validates the activation package build plan; it does not prove the remote host can activate successfully or decrypt its sops secrets.

## Commit & Pull Request Guidelines

Recent commits use concise scoped messages, often in Chinese, such as `home-manager: 加入 rust 相关工具` or `refactor: 重构 flake module 与 nix settings`. Use a short scope followed by the change. Mention affected hosts or modules when relevant. PRs should describe the configuration impact, list validation commands run, and call out secret, cache, or host-registry changes explicitly.

## Security & Configuration Tips

Do not commit decrypted secrets. Add new hosts with `age-recipient` before editing host secret files. Prefer system-level Nix substituter settings in `flake/nix-settings.nix`; avoid ad hoc user-level Nix cache configuration unless it is intentionally host-local.
