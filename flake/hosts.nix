{lib, ...}: let
  hosts = let
    default = {
      arch = "x86_64-linux";
      user = "nemo";
      domestic = true;
      determinate = true; # for darwin
      generic = false; # for linux
      platform = "native"; # for linux
    };
  in {
    "nb-d01" =
      default
      // {
        arch = "aarch64-darwin";
      };
    "dt-w01" =
      default
      // {
        platform = "wsl";
      };
    "cn-x01" =
      default
      // {
        generic = true;
      };
    "sg-a01" =
      default
      // {
        arch = "aarch64-linux";
        domestic = false;
        generic = true;
      };
    # hosts: more hosts here
  };
in {
  flake.hosts = hosts;
  systems = lib.unique (lib.catAttrs "arch" (builtins.attrValues hosts));
}
