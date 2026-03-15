{lib, ...}: let
  hosts = let
    default = {
      arch = "x86_64-linux";
      user = "nemo";
      deploy = true;
      generic = false;
    };
  in {
    "nb-d01" =
      default
      // {
        arch = "aarch64-darwin";
        deploy = false;
      };
    "dt-l01" =
      default
      // {
        deploy = false;
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
        generic = true;
      };
    # hostRegistry: more hosts here
  };
in {
  _module.args.hosts = hosts;
  systems = lib.unique (lib.catAttrs "arch" (builtins.attrValues hosts));
}
