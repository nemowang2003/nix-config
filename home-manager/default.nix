{
  self,
  inputs,
  pkgs,
  lib,
  cfg,
  ...
}: {
  imports =
    [
      inputs.catppuccin.homeModules.catppuccin
      inputs.sops-nix.homeManagerModules.sops
    ]
    ++ self.lib.collect-nix-files ./modules
    ++ self.lib.collect-nix-files ./profiles;

  targets.genericLinux.enable = cfg.platform == "generic";

  catppuccin = {
    enable = true;
    autoEnable = true;
    flavor = "mocha";
  };

  home = {
    username = cfg.user;
    homeDirectory =
      if cfg.isDarwin
      then "/Users/${cfg.user}"
      else "/home/${cfg.user}";

    packages = with pkgs;
      [
        cloudflared
        curl
        fastfetch-unwrapped
        fd
        jq
        python314
        ripgrep
        tokei
        wget
      ]
      ++ lib.optionals cfg.isDarwin [
        darwin.trash
      ];

    shellAliases =
      {
        "-" = "cd -";
        l = "ls -lh";
        ll = "ls -lh";
        la = "ls -lAh";
        diff = "diff --color";
      }
      // (
        if cfg.isDarwin
        then {
          ls = "ls -G";
          rm = "trash";
        }
        else {
          ls = "ls --color=auto";
        }
      );

    sessionVariables =
      {
        LESS = "-R";
        LS_COLORS = "di=1;36:ln=35:so=32:pi=33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43";
      }
      // lib.optionalAttrs cfg.isDarwin {
        LSCOLORS = "Gxfxcxdxbxegedabagacad";
      };
  };
}
