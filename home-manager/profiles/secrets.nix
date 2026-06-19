{
  self,
  config,
  lib,
  hostname,
  ...
}: let
  inherit (self.sops.env) commonFile hostFile;

  mkEnvSecret = {
    name,
    file,
    scope,
  }: {
    inherit name file scope;
    sopsName = "env/${scope}/${name}";
  };

  mkCommonEnvSecret = name:
    mkEnvSecret {
      inherit name;
      file = commonFile;
      scope = "common";
    };

  mkHostEnvSecret = name:
    mkEnvSecret {
      inherit name;
      file = hostFile hostname;
      scope = "hosts/${hostname}";
    };

  commonEnvSecrets = [
    "UCAS_USERNAME"
    "UCAS_PASSWORD"
  ];

  hostEnvSecrets = {
    nb-d01 = [
    ];
    dt-w01 = [
    ];
  };

  currentHostEnvSecrets = hostEnvSecrets.${hostname} or [];

  envSecrets =
    (lib.optionals (builtins.pathExists commonFile) (map mkCommonEnvSecret commonEnvSecrets))
    ++ (lib.optionals (builtins.pathExists (hostFile hostname)) (map mkHostEnvSecret currentHostEnvSecrets));
in {
  sops = {
    age.sshKeyPaths = ["${config.home.homeDirectory}/.ssh/id_ed25519"];

    secrets = builtins.listToAttrs (map (secret: {
        name = secret.sopsName;
        value = {
          sopsFile = secret.file;
          key = secret.name;
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
}
