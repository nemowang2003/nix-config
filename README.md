# nix-config

My pragmatic Nix infrastructure.

## Architecture

This flake manages a fleet of diverse machines (darwin, wsl, native nixos, and generic linux) through a centralized `flake/hosts.nix` registry.

- `hosts/`: Per-host specific configurations.
- `nixos/`, `darwin/`, `home-manager/`: Shared modules.

## Bootstrap

```bash
# 0. edit `flake/hosts.nix`

# 1. install nix (determinate systems), skip this step on nixos
curl -fsSL https://install.determinate.systems/nix | sh -s -- install

# 2. clone
git clone https://github.com/nemowang2003/nix-config.git
git clone git@github.com:nemowang2003/nix-config.git # or consider using ssh agent forwarding

# 3. activate devshell (this may take a while)
nix run nixpkgs#direnv allow

# 4. system rebuild
rebuild

# 5. sync github keys
gh-keysync
```

## Todo

- sops
  - sensitive env
  - per-host configuration
- native nixos hardware configuration

---

**Note**: tailscale is strongly recommended as primary network layer for cross-node access and ssh.
