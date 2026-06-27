{lib, ...}: let
  is-darwin = arch: (lib.systems.elaborate arch).isDarwin;
  is-linux = arch: (lib.systems.elaborate arch).isLinux;
  mkHost = {
    arch ? "x86_64-linux",
    user ? "nemo",
    domestic ? true,
    determinate ? false,
    platform ? "native", # for linux. "native" "wsl" ... for nixos, "generic" for non-nixos
    user-pubkey ? null,
    age-recipient ? null,
  }: {
    inherit arch user domestic determinate platform user-pubkey age-recipient;
    is-darwin = is-darwin arch;
    is-linux = is-linux arch;
  };
  hosts = {
    "nb-d01" = mkHost {
      arch = "aarch64-darwin";
      determinate = true;
      user-pubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAcHLcF1e4Ajy3J6mSX67FIUVN736GhFDViiTwAFDEmo nemo@nb-d01";
      age-recipient = "age1jh9zeajeu9mxw3sakfcqd7eau2kvf07r82ev9tsmz4jqz962w56q2xwvuq";
    };
    "dt-w01" = mkHost {
      platform = "wsl";
      user-pubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFmKIHSNffGDt7/rf4ADMV6acXwndDh9FU8JYj2ouIDt nemo@dt-w01";
      age-recipient = "age1p73za2fx80h3wtwv5wl8atd2eslf50m94c0dy9zl2pls94yumavqg8t4cu";
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
  user-pubkeys =
    lib.mapAttrsToList
    (hostname: cfg: cfg.user-pubkey)
    (lib.filterAttrs (hostname: cfg: cfg.user-pubkey != null) hosts);
in {
  flake = {inherit hosts user-pubkeys;};
  systems = lib.unique (lib.catAttrs "arch" (builtins.attrValues hosts));
}
