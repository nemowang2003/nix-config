# github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
{lib, ...}: let
  mkHost = {
    arch ? "x86_64-linux",
    user ? "nemo",
    domestic ? true,
    determinate ? true, # for darwin
    platform ? "native", # for linux. "native" "wsl" ... for nixos, "generic" for non-nixos
    userPubkey ? null,
    ageRecipient ? null,
  }: {
    inherit arch user domestic determinate platform userPubkey ageRecipient;
  };
  hosts = {
    "nb-d01" = mkHost {
      arch = "aarch64-darwin";
      userPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAcHLcF1e4Ajy3J6mSX67FIUVN736GhFDViiTwAFDEmo nemo@nb-d01";
      ageRecipient = "age1jh9zeajeu9mxw3sakfcqd7eau2kvf07r82ev9tsmz4jqz962w56q2xwvuq";
    };
    "dt-w01" = mkHost {
      platform = "wsl";
      userPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFmKIHSNffGDt7/rf4ADMV6acXwndDh9FU8JYj2ouIDt nemo@dt-w01";
      ageRecipient = "age1p73za2fx80h3wtwv5wl8atd2eslf50m94c0dy9zl2pls94yumavqg8t4cu";
    };
    "sg-x01" = mkHost {
      domestic = false;
      platform = "generic";
    };
    "sg-a01" = mkHost {
      arch = "aarch64-linux";
      domestic = false;
      platform = "generic";
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
