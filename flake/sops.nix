{
  self,
  lib,
  ...
}: let
  common-dir = ../secrets/common;
  trusted-dir = ../secrets/trusted;
  hosts-dir = ../secrets/hosts;
  host-recipients =
    lib.mapAttrs
    (_: cfg: cfg.age-recipient)
    (lib.filterAttrs (_: cfg: cfg.age-recipient != null) self.hosts);
  trusted-recipients =
    lib.mapAttrs
    (_: cfg: cfg.age-recipient)
    (lib.filterAttrs (_: cfg: cfg.trusted && cfg.age-recipient != null) self.hosts);
in {
  flake.sops = {
    dirs = {
      common = common-dir;
      trusted = trusted-dir;
      host = hostname: hosts-dir + "/${hostname}";
    };

    text = {
      routes-file = common-dir + "/routes.json";
      twofa-file = trusted-dir + "/2fa.json";
      public-ips-file = common-dir + "/public-ips.json";
    };

    env = {
      common-file = common-dir + "/.env";
      trusted-file = trusted-dir + "/.env";
      host-file = hostname: hosts-dir + "/${hostname}/.env";
      files-for-host = hostname: let
        cfg = self.hosts.${hostname};
      in
        builtins.filter builtins.pathExists
        (
          lib.optionals (cfg.age-recipient != null) [
            (common-dir + "/.env")
          ]
          ++ lib.optionals (cfg.trusted && cfg.age-recipient != null) [
            (trusted-dir + "/.env")
          ]
          ++ [
            (hosts-dir + "/${hostname}/.env")
          ]
        );
    };

    yaml = {
      creation_rules =
        [
          {
            path_regex = "secrets/common/.*$";
            key_groups = [
              {
                age = lib.attrValues host-recipients;
              }
            ];
          }
          {
            path_regex = "secrets/trusted/.*$";
            key_groups = [
              {
                age = lib.attrValues trusted-recipients;
              }
            ];
          }
        ]
        ++ lib.mapAttrsToList
        (hostname: recipient: {
          path_regex = "secrets/hosts/${hostname}/.*$";
          key_groups = [
            {
              age = [recipient];
            }
          ];
        })
        host-recipients;
    };
  };
}
