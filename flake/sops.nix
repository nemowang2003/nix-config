{
  self,
  lib,
  ...
}: let
  env-dir = ../secrets/env;
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
    env = {
      common-file = env-dir + "/common.yaml";
      trusted-file = env-dir + "/trusted.yaml";
      host-file = hostname: env-dir + "/hosts/${hostname}.yaml";
      files-for-host = hostname: let
        cfg = self.hosts.${hostname};
      in
        builtins.filter builtins.pathExists
        (
          lib.optionals (cfg.age-recipient != null) [
            (env-dir + "/common.yaml")
          ]
          ++ lib.optionals (cfg.trusted && cfg.age-recipient != null) [
            (env-dir + "/trusted.yaml")
          ]
          ++ [
            (env-dir + "/hosts/${hostname}.yaml")
          ]
        );
    };

    yaml = {
      creation_rules =
        [
          {
            path_regex = "secrets/text/common\\.yaml$";
            key_groups = [
              {
                age = lib.attrValues host-recipients;
              }
            ];
          }
          {
            path_regex = "secrets/env/common\\.yaml$";
            key_groups = [
              {
                age = lib.attrValues host-recipients;
              }
            ];
          }
          {
            path_regex = "secrets/env/trusted\\.yaml$";
            key_groups = [
              {
                age = lib.attrValues trusted-recipients;
              }
            ];
          }
        ]
        ++ lib.mapAttrsToList
        (hostname: recipient: {
          path_regex = "secrets/env/hosts/${hostname}\\.yaml$";
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
