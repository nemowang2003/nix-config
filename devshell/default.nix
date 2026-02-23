{ inputs, lib, pkgs, ... }: 

{
  packages = with pkgs; [
    age
    alejandra
    home-manager
    sops
    ssh-to-age
    nixd
  ] ++ lib.optionals stdenv.isDarwin [
    inputs.darwin.packages.${pkgs.system}.default
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
      help = "home-manager switch";
      command = ''
        home-manager switch --flake "$PRJ_ROOT"
      '';
    }
    {
      name = "rebuild";
      help = "system rebuild + home-manager switch";
      command = if pkgs.stdenv.isDarwin then ''
        sudo darwin-rebuild switch --flake "$PRJ_ROOT" && hms
      '' else ''
        if [[ -e /etc/NIXOS ]]; then
          sudo nixos-rebuild switch --flake "$PRJ_ROOT" && hms
        else
          echo "Generic Linux detected, skipping system rebuild..."
          hms
        fi
      '';
    }
  ];
}
