{
  self,
  lib,
  ...
}: let
  envDir = ../secrets/env;
  hostRecipients =
    lib.mapAttrs
    (_: cfg: cfg.ageRecipient)
    (lib.filterAttrs (_: cfg: cfg.ageRecipient != null) self.hosts);
in {
  flake.sops = {
    env = {
      commonFile = envDir + "/common.yaml";
      hostFile = hostname: envDir + "/hosts/${hostname}.yaml";
      filesForHost = hostname:
        builtins.filter builtins.pathExists [
          (envDir + "/common.yaml")
          (envDir + "/hosts/${hostname}.yaml")
        ];
    };

    yaml = {
      creation_rules =
        [
          {
            path_regex = "secrets/env/common\\.yaml$";
            key_groups = [
              {
                age = lib.attrValues hostRecipients;
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
        hostRecipients;
    };
  };
}
