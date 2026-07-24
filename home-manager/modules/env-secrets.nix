{
  self,
  config,
  lib,
  hostname,
  cfg,
  ...
}: let
  inherit (self.sops.env) commonFile trustedFile hostFile;
  inherit (lib) mkOption types;

  mkEnvSecret = {
    name,
    key,
    file,
    scope,
  }: {
    inherit name key file scope;
    sopsName = "env/${scope}/${name}";
  };

  mkCommonEnvSecret = name: secret:
    mkEnvSecret {
      inherit name;
      inherit (secret) key;
      file = commonFile;
      scope = "common";
    };

  mkTrustedEnvSecret = name: secret:
    mkEnvSecret {
      inherit name;
      inherit (secret) key;
      file = trustedFile;
      scope = "trusted";
    };

  mkHostEnvSecret = name: secret:
    mkEnvSecret {
      inherit name;
      inherit (secret) key;
      file = hostFile hostname;
      scope = "hosts/${hostname}";
    };

  hasAgeRecipient = cfg.age-recipient != null;

  declaredEnvSecrets = lib.filterAttrs (_: secret: secret.enable) config.my.env-secrets;

  envSecrets = lib.concatLists (lib.mapAttrsToList (
      name: secret:
        if secret.group == "common"
        then lib.optionals (hasAgeRecipient && builtins.pathExists commonFile) [(mkCommonEnvSecret name secret)]
        else if secret.group == "trusted"
        then lib.optionals (hasAgeRecipient && cfg.trusted && builtins.pathExists trustedFile) [(mkTrustedEnvSecret name secret)]
        else lib.optionals (hasAgeRecipient && builtins.pathExists (hostFile hostname)) [(mkHostEnvSecret name secret)]
    )
    declaredEnvSecrets);
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
          name = secret.sopsName;
          value = {
            sopsFile = secret.file;
            key = secret.key;
          };
        })
        envSecrets);

      templates."env/secrets.env".content =
        lib.concatMapStrings (secret: ''
          export ${secret.name}="${config.sops.placeholder.${secret.sopsName}}"
        '')
        envSecrets;
    };

    programs.zsh.initContent = lib.mkIf (envSecrets != []) (lib.mkBefore ''
      if [[ -r "${config.sops.templates."env/secrets.env".path}" ]]; then
        source "${config.sops.templates."env/secrets.env".path}"
      fi
    '');
  };
}
