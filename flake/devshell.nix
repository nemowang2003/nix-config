{inputs, ...}: {
  imports = [
    inputs.devshell.flakeModule
  ];

  perSystem = {
    pkgs,
    lib,
    system,
    ...
  }: {
    devshells.default = {
      packages = with pkgs;
        [
          age
          home-manager
          sops
          ssh-to-age
        ]
        ++ lib.optionals pkgs.stdenv.isDarwin [
          inputs.darwin.packages.${system}.default
        ];

      env = [
        {
          name = "SOPS_AGE_KEY";
          eval = "$(ssh-to-age -private-key -i \"$HOME\"/.ssh/id_ed25519)";
        }
      ];

      commands = [
        {
          name = "hms";
          category = "management";
          help = "home-manager switch";
          command = ''
            set -x
            home-manager switch --flake "$PRJ_ROOT" -b before-home-manager
          '';
        }
        {
          name = "rebuild";
          category = "management";
          help = "system rebuild + home-manager switch";
          command =
            if pkgs.stdenv.isDarwin
            then ''
              set -x
              sudo darwin-rebuild switch --flake "$PRJ_ROOT" && hms
            ''
            else ''
              if [[ -e /etc/NIXOS ]]; then
                set -x
                sudo nixos-rebuild switch --flake "$PRJ_ROOT" && hms
              else
                echo "Generic Linux detected, skipping system rebuild..."
                hms
              fi
            '';
        }
        {
          name = "update";
          category = "management";
          help = "nix flake update and auto-commit";
          command = ''
            set -x
            ${lib.optionalString pkgs.stdenv.isDarwin "ulimit -n 4096"}
            nix flake update && git commit flake.lock -m "update: $(date +%Y-%m-%d)" && rebuild
          '';
        }
      ];
    };
  };
}
