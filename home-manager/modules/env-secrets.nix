{
  self,
  config,
  lib,
  hostname,
  cfg,
  ...
}: let
  inherit (self.sops.env) common-file trusted-file host-file;
  inherit (lib) mkOption types;

  mkEnvSecret = {
    name,
    key,
    file,
    scope,
  }: {
    inherit name key file scope;
    sops-name = "env/${scope}/${name}";
  };

  mkCommon = name: secret:
    mkEnvSecret {
      inherit name;
      inherit (secret) key;
      file = common-file;
      scope = "common";
    };

  mkTrusted = name: secret:
    mkEnvSecret {
      inherit name;
      inherit (secret) key;
      file = trusted-file;
      scope = "trusted";
    };

  mkHost = name: secret:
    mkEnvSecret {
      inherit name;
      inherit (secret) key;
      file = host-file hostname;
      scope = "hosts/${hostname}";
    };

  has-age-recipient = cfg.age-recipient != null;

  declared-env-secrets = lib.filterAttrs (_: secret: secret.enable) config.my.env-secrets;

  env-secrets = lib.concatLists (lib.mapAttrsToList (
      name: secret:
        if secret.group == "common"
        then lib.optionals (has-age-recipient && builtins.pathExists common-file) [(mkCommon name secret)]
        else if secret.group == "trusted"
        then lib.optionals (has-age-recipient && cfg.trusted && builtins.pathExists trusted-file) [(mkTrusted name secret)]
        else lib.optionals (has-age-recipient && builtins.pathExists (host-file hostname)) [(mkHost name secret)]
    )
    declared-env-secrets);
in {
  options.my.env-secrets = mkOption {
    type = types.attrsOf (types.submodule ({name, ...}: {
      options = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to materialize this environment secret.";
        };

        key = mkOption {
          type = types.str;
          default = name;
          description = "Key name in the sops file.";
        };

        group = mkOption {
          type = types.enum ["common" "trusted" "host"];
          default = "host";
          description = "Recipient group backing this environment secret.";
        };
      };
    }));
    default = {};
    description = "Private registry of environment secrets requested by profiles and host modules.";
  };

  config = {
    sops = {
      age.sshKeyPaths = ["${config.home.homeDirectory}/.ssh/id_ed25519"];

      secrets = builtins.listToAttrs (map (secret: {
          name = secret.sops-name;
          value = {
            sopsFile = secret.file;
            key = secret.key;
          };
        })
        env-secrets);

      templates."env/secrets.env".content =
        lib.concatMapStrings (secret: ''
          export ${secret.name}="${config.sops.placeholder.${secret.sops-name}}"
        '')
        env-secrets;
    };

    programs.zsh.initContent = lib.mkIf (env-secrets != []) (lib.mkBefore ''
      if [[ -r "${config.sops.templates."env/secrets.env".path}" ]]; then
        source "${config.sops.templates."env/secrets.env".path}"
      fi
    '');
  };
}
