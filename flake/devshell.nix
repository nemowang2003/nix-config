{
  self,
  inputs,
  ...
}: {
  imports = [
    inputs.devshell.flakeModule
  ];

  perSystem = {
    pkgs,
    lib,
    system,
    ...
  }: let
    sops-yaml = inputs.nixago.lib.${system}.make {
      output = ".sops.yaml";
      format = "yaml";
      data = self.sops.yaml;
      hook.mode = "copy";
    };
  in {
    packages.sops-yaml = sops-yaml.configFile;

    devshells.default = {
      devshell.startup.sops-yaml.text = sops-yaml.shellHook;

      packages = with pkgs;
        [
          age
          gh
          home-manager
          jq
          sops
        ]
        ++ lib.optionals pkgs.stdenv.isDarwin [
          inputs.darwin.packages.${system}.default
        ];

      env = [
        {
          name = "SOPS_AGE_KEY";
          eval = "$(${lib.getExe pkgs.ssh-to-age} -private-key -i \"$HOME/.ssh/id_ed25519\")";
        }
      ];

      commands = [
        {
          name = "hms";
          category = "deployment";
          help = "home-manager switch";
          command = ''
            set -x
            home-manager switch --flake "$PRJ_ROOT" -b before-home-manager
          '';
        }
        {
          name = "rebuild";
          category = "deployment";
          help = "system rebuild + home-manager switch";
          command =
            if pkgs.stdenv.isDarwin
            then ''
              set -x
              sudo darwin-rebuild switch --flake "$PRJ_ROOT" && hms
            ''
            else ''
              set -x
              if [[ -e /etc/NIXOS ]]; then
                sudo nixos-rebuild switch --flake "$PRJ_ROOT" && hms
              else
                echo "Generic Linux detected, skipping system rebuild..."
                hms
              fi
            '';
        }
        {
          name = "update";
          category = "deployment";
          help = "nix flake update";
          command = ''
            set -x
            ${lib.optionalString pkgs.stdenv.isDarwin "ulimit -n 4096"}
            nix flake update && rebuild
          '';
        }
        {
          name = "gh-keysync";
          category = "authentication";
          help = "gh ssh-key add";
          command = ''
            set -x
            set -e
            nix eval "$PRJ_ROOT"#user-pubkeys --json | jq -r '.[]' | while read -r pubkey type comment; do
              name="''${comment#*@}"
              key="$pubkey $type $comment"
              gh ssh-key add - --title "$name" <<< "$key"
              gh ssh-key add - --type signing --title "$name" <<< "$key"
            done
          '';
        }
        {
          name = "sops-edit-env";
          category = "secrets";
          help = "sops secrets/env/common.yaml / sops secrets/env/hosts/<hostname>.yaml";
          command = ''
            mkdir -p "$PRJ_ROOT/secrets/env/hosts"
            set -x
            if [[ $# -eq 0 ]]; then
              sops "$PRJ_ROOT/secrets/env/common.yaml"
            else
              sops "$PRJ_ROOT/secrets/env/hosts/$1.yaml"
            fi
          '';
        }
      ];
    };
  };
}
