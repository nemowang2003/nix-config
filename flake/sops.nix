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
in {
  flake.sops = {
    env = {
      commonFile = env-dir + "/common.yaml";
      hostFile = hostname: env-dir + "/hosts/${hostname}.yaml";
      filesForHost = hostname:
        builtins.filter builtins.pathExists [
          (env-dir + "/common.yaml")
          (env-dir + "/hosts/${hostname}.yaml")
        ];
    };

    yaml = {
      creation_rules =
        [
          {
            path_regex = "secrets/env/common\\.yaml$";
            key_groups = [
              {
                age = lib.attrValues host-recipients;
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
