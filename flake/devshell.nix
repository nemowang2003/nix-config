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
    jq = lib.getExe pkgs.jq;
    gh = lib.getExe pkgs.gh;
    home-manager = lib.getExe pkgs.home-manager;
  in {
    formatter = alejandra-format;

    packages.sops-yaml = sops-yaml.configFile;

    devshells.default = {
      packages = [pkgs.sops];

      devshell.startup.sops-yaml.text = sops-yaml.shellHook;

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
            set -euo pipefail
            nix eval --impure "$PRJ_ROOT#user-pubkeys" --json >/dev/null

            nix eval --impure "$PRJ_ROOT#hosts" --json \
              | ${jq} -r 'to_entries[] | [.key, .value.user, .value.isDarwin, .value.isLinux, .value.platform] | @tsv' \
              | while IFS=$'\t' read -r host user isDarwin isLinux platform; do
                home="$user@$host"
                echo "eval homeConfigurations.\"$home\""
                nix eval --impure "$PRJ_ROOT#homeConfigurations.\"$home\".config.home.stateVersion" >/dev/null

                if [[ "$isDarwin" == "true" ]]; then
                  echo "eval darwinConfigurations.$host"
                  nix eval --impure "$PRJ_ROOT#darwinConfigurations.$host.config.system.stateVersion" >/dev/null
                fi

                if [[ "$isLinux" == "true" && "$platform" != "generic" ]]; then
                  echo "eval nixosConfigurations.$host"
                  nix eval --impure "$PRJ_ROOT#nixosConfigurations.$host.config.system.stateVersion" >/dev/null
                fi

                if [[ "$platform" == "generic" ]]; then
                  echo "eval genericConfigurations.$host"
                  nix eval --impure "$PRJ_ROOT#genericConfigurations.$host.config.system.build.activationPackage.drvPath" >/dev/null
                fi
              done
          '';
        }
        {
          name = "check-activation";
          category = "checks";
          help = "dry-run Home Manager activation packages for all declared hosts";
          command = ''
            set -euo pipefail

            nix eval "$PRJ_ROOT#hosts" --json \
              | ${jq} -r 'to_entries[] | [.key, .value.user] | @tsv' \
              | while IFS=$'\t' read -r host user; do
                home="$user@$host"
                attr="$PRJ_ROOT#homeConfigurations.\"$home\".activationPackage"
                log="$(mktemp "''${TMPDIR:-/tmp}/check-activation.XXXXXX")"

                echo "dry-run homeConfigurations.\"$home\".activationPackage"
                if nix build --impure --dry-run "$attr" >"$log" 2>&1; then
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
            set -euo pipefail
            ${home-manager} switch --impure --flake "$PRJ_ROOT" -b before-home-manager
          '';
        }
        {
          name = "rebuild";
          category = "deployment";
          help = "system rebuild + home-manager switch";
          command =
            if pkgs.stdenv.hostPlatform.isDarwin
            then ''
              set -euo pipefail
              sudo ${lib.getExe inputs.darwin.packages.${system}.default} switch --impure --flake "$PRJ_ROOT" && hms
            ''
            else ''
              set -euo pipefail
              if [[ -e /etc/NIXOS ]]; then
                sudo nixos-rebuild switch --impure --flake "$PRJ_ROOT" && hms
              else
                sudo env "PATH=$PATH" "${lib.getExe self.packages.${system}.generic-rebuild}" switch --flake "$PRJ_ROOT" && hms
              fi
            '';
        }
        {
          name = "update";
          category = "deployment";
          help = "nix flake update";
          command = ''
            set -euo pipefail
            nix flake update && rebuild
          '';
        }
        {
          name = "gh-keysync";
          category = "authentication";
          help = "gh ssh-key add";
          command = ''
            set -euo pipefail
            nix eval --impure "$PRJ_ROOT"#user-pubkeys --json | ${jq} -r '.[]' | while read -r pubkey type comment; do
              name="''${comment#*@}"
              key="$pubkey $type $comment"
              ${gh} ssh-key add - --title "$name" <<< "$key"
              ${gh} ssh-key add - --type signing --title "$name" <<< "$key"
            done
          '';
        }
      ];
    };
  };
}
