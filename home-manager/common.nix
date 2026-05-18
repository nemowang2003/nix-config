{
  inputs,
  pkgs,
  lib,
  cfg,
  ...
}: {
  imports =
    [
      inputs.catppuccin.homeModules.catppuccin
    ]
    ++ builtins.attrValues (inputs.haumea.lib.load {
      src = ./profiles;
      loader = inputs.haumea.lib.loaders.path;
      transformer = [
        (
          cursor: dir:
            if dir ? default
            then dir.default
            else dir
        )
      ];
    });

  targets.genericLinux.enable = cfg.platform == "generic";

  catppuccin = {
    enable = true;
    flavor = "mocha";
  };

  home = {
    username = cfg.user;
    homeDirectory =
      if pkgs.stdenv.isDarwin
      then "/Users/${cfg.user}"
      else "/home/${cfg.user}";

    packages = with pkgs;
      [
        cloudflared
        curl
        fastfetchMinimal
        fd
        jq
        python314
        ripgrep
        tokei
        wget
      ]
      ++ lib.optionals stdenv.isDarwin [
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
      // lib.optionalAttrs pkgs.stdenv.isDarwin {
        ls = "ls -G";
        rm = "trash";
      }
      // lib.optionalAttrs (!pkgs.stdenv.isDarwin) {
        ls = "ls --color=auto";
      };

    sessionVariables =
      {
        LESS = "-R";
        LS_COLORS = "di=1;36:ln=35:so=32:pi=33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43";
      }
      // lib.optionalAttrs pkgs.stdenv.isDarwin {
        LSCOLORS = "Gxfxcxdxbxegedabagacad";
      };
  };
}
