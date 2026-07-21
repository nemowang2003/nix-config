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
    alejandra-format = pkgs.writeShellApplication {
      name = "alejandra-format";
      runtimeInputs = [pkgs.alejandra];
      text = ''
        if [[ $# -eq 0 ]]; then
          set -- .
        fi

        exec alejandra "$@"
      '';
    };
  in {
    formatter = alejandra-format;

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
          name = "check-eval";
          category = "checks";
          help = "evaluate flake outputs for all declared hosts";
          command = ''
            set -e
            nix eval "$PRJ_ROOT#user-pubkeys" --json >/dev/null

            nix eval "$PRJ_ROOT#hosts" --json \
              | jq -r 'to_entries[] | [.key, .value.user, .value.isDarwin, .value.isLinux, .value.platform] | @tsv' \
              | while IFS=$'\t' read -r host user is_darwin is_linux platform; do
                home="$user@$host"
                echo "eval homeConfigurations.\"$home\""
                nix eval "$PRJ_ROOT#homeConfigurations.\"$home\".config.home.stateVersion" >/dev/null

                if [[ "$is_darwin" == "true" ]]; then
                  echo "eval darwinConfigurations.$host"
                  nix eval "$PRJ_ROOT#darwinConfigurations.$host.config.system.stateVersion" >/dev/null
                fi

                if [[ "$is_linux" == "true" && "$platform" != "generic" ]]; then
                  echo "eval nixosConfigurations.$host"
                  nix eval "$PRJ_ROOT#nixosConfigurations.$host.config.system.stateVersion" >/dev/null
                fi
              done
          '';
        }
        {
          name = "check-activation";
          category = "checks";
          help = "dry-run Home Manager activation packages for all declared hosts";
          command = ''
            set -e

            nix eval "$PRJ_ROOT#hosts" --json \
              | jq -r 'to_entries[] | [.key, .value.user] | @tsv' \
              | while IFS=$'\t' read -r host user; do
                home="$user@$host"
                attr="$PRJ_ROOT#homeConfigurations.\"$home\".activationPackage"
                log="$(mktemp "''${TMPDIR:-/tmp}/check-activation.XXXXXX")"

                echo "dry-run homeConfigurations.\"$home\".activationPackage"
                if nix build --dry-run "$attr" >"$log" 2>&1; then
                  rm -f "$log"
                else
                  cat "$log" >&2
                  rm -f "$log"
                  exit 1
                fi
              done
          '';
        }
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
