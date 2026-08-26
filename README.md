# nix-config

My pragmatic Nix infrastructure.

## Architecture

This flake manages a fleet of diverse machines (darwin, wsl, native nixos, and generic linux) through a centralized `flake/hosts.nix` registry.

- `hosts/`: Per-host specific configurations.
- `nixos/`, `darwin/`, `generic/`, `home-manager/`: Shared modules and profiles.
- `flake/`: Flake modules: host registry, configuration builders, devshell, and overlays.
- `packages/`: Reusable executables (`notify`, `codex-notify`, `generic-rebuild`), exported as the flake's `packages` output.
- `lib/`: Shared helper functions.
- `secrets/`: sops-encrypted environment secrets.

## Bootstrap

```bash
# 0. edit `flake/hosts.nix`

# 1. install nix (determinate systems), skip this step on nixos
curl -fsSL https://install.determinate.systems/nix | sh -s -- install

# 2. clone
git clone https://github.com/nemowang2003/nix-config.git
git clone git@github.com:nemowang2003/nix-config.git # or consider using ssh agent forwarding

# 3. enter the devshell (this may take a while)
nix develop

# 4. system rebuild
rebuild

# 5. sync github keys
gh-keysync
```

With direnv installed, `direnv allow` activates the devshell automatically when entering the repository.

## Checks & deployment

- `check-eval`: evaluate flake outputs for all declared hosts.
- `check-activation`: dry-run Home Manager activation packages for all hosts.
- `hms`: run `home-manager switch` only.
- `rebuild`: host system activation, then `hms`.
- `generic-rebuild [build|switch]`: build or activate a generic Linux host's Nix settings (`switch` requires root).
- `sops-edit-env [common|trusted|hostname]`: edit encrypted environment secrets.

Secrets are encrypted with sops/age. The devshell derives `SOPS_AGE_KEY` from `~/.ssh/id_ed25519`, so that key must exist before editing secrets.

---

**Note**: tailscale is strongly recommended as primary network layer for cross-node access and ssh.
