# github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
{lib, ...}: let
  mkHost = {
    arch ? "x86_64-linux",
    user ? "nemo",
    domestic ? true,
    determinate ? true, # for darwin
    platform ? "native", # for linux. "native" "wsl" ... for nixos, "generic" for non-nixos
    hostPubkey,
    userPubkey ? null,
  }: {
    inherit arch user domestic determinate platform hostPubkey userPubkey;
  };
  hosts = {
    "nb-d01" = mkHost {
      arch = "aarch64-darwin";
      hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIwRPj5gZo51Q3WWNH41W2Lj6SrFiCeRKdS8/CoKHV6z";
      userPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAcHLcF1e4Ajy3J6mSX67FIUVN736GhFDViiTwAFDEmo nemo@nb-d01";
    };
    "dt-w01" = mkHost {
      platform = "wsl";
      hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGJvk/JDDhDfbwW68N9OU90JJwYIMLuWmchbV6sr/Abe";
      userPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFmKIHSNffGDt7/rf4ADMV6acXwndDh9FU8JYj2ouIDt nemo@dt-w01";
    };
    "sg-x01" = mkHost {
      domestic = false;
      platform = "generic";
      hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM2oMCcdgggK2dFpzKPA2cBpoLB3yYMSALPbAkKoneyo";
    };
    "sg-a01" = mkHost {
      arch = "aarch64-linux";
      domestic = false;
      platform = "generic";
      hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII3no7flD8nkgp5n63JVFug+IajdrKtKHm7/17ZS6dXx";
    };
    # hosts: more hosts here
  };
  userPubkeys =
    lib.mapAttrsToList
    (hostname: cfg: cfg.userPubkey)
    (lib.filterAttrs (hostname: cfg: cfg.userPubkey != null) hosts);
in {
  flake = {inherit hosts userPubkeys;};
  systems = lib.unique (lib.catAttrs "arch" (builtins.attrValues hosts));
}
