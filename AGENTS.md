# Repository Guidelines

## Project Structure & Module Organization

This repository is a Nix flake for personal machine configuration across macOS, NixOS, WSL, and generic Linux.

- `flake.nix` declares inputs and loads flake modules from `flake/`.
- `flake/hosts.nix` is the host registry. Add machines here before creating host modules.
- `flake/configurations.nix` builds `darwinConfigurations`, `nixosConfigurations`, and `genericConfigurations` for generic Linux hosts, plus standalone `homeConfigurations` for every host.
- `darwin/`, `nixos/`, `generic/`, and `home-manager/` contain shared modules and profiles.
- `generic/modules/` declares generic system options and builds the nix.conf/activation package; `generic/profiles/` provides the default generic Linux configuration; `hosts/<hostname>/generic/` overrides it per host.
- `packages/` is loaded by `flake/packages.nix` via `inputs.haumea.lib.load`, with `loader = loaders.callPackage` and `transformer = self.lib.haumea.force-shallow-transformer` (defined in `lib/haumea.nix`): a top-level `.nix` file becomes a package, and a directory must contain `default.nix` (which is exported; other files are loaded but not exported). The result is the flake's `packages` output; modules reach it through `self.packages.${pkgs.stdenv.hostPlatform.system}.<name>` rather than a nixpkgs overlay.
- Standalone reusable applications live in separate repositories with flake inputs (audio-transcribe, llama-on-demand, ja2zh-srt); host installation and service choices stay under `hosts/`. External Python applications with `uv.lock` use uv2nix and follow the root `pyproject-nix`, `uv2nix`, and `pyproject-build-systems` inputs. Keep configuration-coupled local packages in `packages/<name>/`, with `default.nix` as the Nix entrypoint. Python applications use `pyproject.toml` (`uv_build` and `[project.scripts]`), `src/<module>/__init__.py`, and `tests/`; build them with `self.lib.python-application`. Single-file applications define `main()` directly in `__init__.py`, without an `if __name__ == "__main__"` block; script entries use `<module>:main`. Command names may differ from Python module names, e.g. `2fa` imports `totp`, configured with `tool.uv.build-backend.module-name`. Keep the backend version range compatible with the locked Nixpkgs `uv-build` version. Shell tools keep their script in `main.sh`.
- Put zsh completions in `packages/<name>/_<command>`, using `#compdef <command>` and a named completion function. The shared Python helper installs matching files for `[project.scripts]` automatically; shell packages install them with `installShellFiles`.
- `home-manager/modules/` declares private Home Manager options and shared glue, such as `my.*`.
- `home-manager/profiles/` contains concrete program, language, and secret profiles.
- `hosts/<hostname>/{darwin,nixos,generic,home-manager}/default.nix` contains per-host overrides.
- `secrets/{common,trusted,hosts}/` stores sops-managed encrypted secrets, grouped by access scope.
- `lib/` contains shared helper functions; `lib/models.nix` is the single source of model facts (identity, context/output limits, reasoning, vision) and provider endpoints consumed by the agent profiles. Client-specific defaults and prompt scaffolding live in each client's renderer, e.g. `home-manager/profiles/agents/codex/catalog-template.json`.

## Build, Test, and Development Commands

Use the devshell via direnv or `nix develop`.

- `hms`: run `home-manager switch --flake "$PRJ_ROOT"`.
- `rebuild`: run the host system activation, then `hms`; on generic Linux it installs the system Nix configuration first.
- `nix run .#generic-rebuild [build|switch] [--flake <flake>]`: build or activate the current host's `genericConfigurations.<host>.config.system.build.activationPackage`; it resolves the host from `hostname -s`, and `switch` must run as root (the `rebuild` devshell command calls it on generic Linux).
- `update`: require a clean Git worktree, run `nix flake update`, commit tracked changes as `update: YYYY-MM-DD`, then run `rebuild`.
- `nix flake check`: run the current system's Python package tests and evaluate configurations for all hosts declared in `.#hosts`.
- `check-activation`: dry-run Home Manager activation packages for all hosts declared in `.#hosts`.
- `gh-keysync`: publish declared SSH public keys to GitHub.
- `sops <path>`: edit encrypted secrets in-place (e.g. `sops secrets/trusted/2fa.json`);
  the devshell startup hook keeps `.sops.yaml` in sync so recipients are picked
  from each path's creation rule.

Useful low-level checks:

```bash
nix eval .#homeConfigurations."nemo@$(hostname -s)".config.home.stateVersion
nix eval .#user-pubkeys --json
```

## Coding Style & Naming Conventions

### Interface documentation

Maintain [flake/README.md](flake/README.md) as the navigation index for public
flake output entrypoints (`self.*`). Maintain `modules/README.md` in module
directories that declare private `my.*` option groups; the current indexes are
[Home Manager](home-manager/modules/README.md) and
[Darwin](darwin/modules/README.md).

When adding, removing, or renaming an output entrypoint or private option group,
or changing its purpose or usage, update the corresponding README in the same
change. Internal implementation changes do not require README edits. Document
groups, definition locations, consumers, and brief usage examples; keep exact
field types, defaults, and constraints in module option declarations. Do not
enumerate every host, package, or nested field, and do not create an empty index
for module directories without private options.

### Code conventions

Write Nix with two-space indentation and prefer small, composable modules. Attribute names in new local metadata use kebab-case, such as `user-pubkeys`, `age-recipient`, and `build-nix-settings`. Keep host-independent logic in shared modules; keep host-specific choices under `hosts/<hostname>/`.

Prefer kebab-case for local Nix variable and helper-function names as well (`agent-languages`, `codex-notify`). Short, conventional helpers such as `isDarwin`, `mkHost`, and upstream library functions like `mkOption` may remain camelCase; do not rename upstream option attributes or framework-provided arguments.

Use `my.*` for private cross-module metadata that is not part of an upstream option namespace. Current private registries include `my.nix-homebrew` for nix-homebrew integration, `my.lsp.servers` for reusable LSP server commands, `my.languages` for language-level LSP and formatter declarations, `my.codex` for mutable Codex configuration, `my.skland` for Skland auto-sign wiring, and `my.secrets` (files, twofa) for sops-backed secret materialization; environment variables are exported wholesale from `secrets/{common,trusted,hosts}/env`.

Format Nix and Python files together:

```bash
nix fmt
```

The flake formatter uses treefmt to run Alejandra for Nix and
`ruff check --fix-only` followed by `ruff format` for Python, matching Helix's
Python formatter. Pass file paths after `--` to limit formatting, or use
`nix fmt -- --fail-on-change` to detect changes (this also formats the files).
Ruff settings and nixago generation are declared in `flake/formatter.nix`, shared
with Home Manager's global configuration through `self.formatter-settings.ruff`,
and copied to the ignored `ruff.toml` by nixago when entering
the devshell. Change the Nix declaration and regenerate with `nix develop`;
the generated `ruff.toml` is not tracked by Git.

## Testing Guidelines

Run the flake checks before switching. They include Python unit tests for `2fa`, `codex-notify`, `codex-wecom-relay`, and `audio-transcribe`, plus evaluation of every declared host:

```bash
nix flake check
```

`flake/checks.nix` automatically collects each package's `passthru.tests` as
`<package>-<test>`. The shared Python application helper exposes a `unit` test
when a `tests/` directory exists, using unittest discovery against `src/`.
Runtime dependencies are available by default; `test-dependencies` can override
them when tests use mocks (as for audio transcription). Packages without tests
do not get an empty check. These source tests do not build the application;
build changed packages separately to verify packaging and entrypoint imports.

For risky Home Manager changes, run `check-activation` before `hms` or `rebuild`. It can dry-run non-local architectures, but it only validates the activation package build plan; it does not prove the remote host can activate successfully or decrypt its sops secrets.

## Pull Request Guidelines

PRs should describe the configuration impact, list validation commands run, and call out secret, cache, or host-registry changes explicitly.

## Security & Configuration Tips

Do not commit decrypted secrets. Add new hosts with `age-recipient` before editing host secret files. Prefer system-level Nix substituter settings in `flake/nix-settings.nix`; avoid ad hoc user-level Nix cache configuration unless it is intentionally host-local.
