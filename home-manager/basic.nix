{
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./profiles/git.nix
    ./profiles/helix.nix
    ./profiles/zsh
  ];

  config = lib.mkMerge [
    # base
    {
      catppuccin.enable = true;
      catppuccin.flavor = "mocha";

      home = {
        packages = with pkgs; [
          cloudflared
          curl
          darwin.trash
          python314
          tokei
          wget
        ];

        shellAliases =
          {
            "-" = "cd -";
            l = "ls -lh";
            ll = "ls -lh";
            la = "ls -lAh";
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

    # bat
    {
      programs.bat = {
        enable = true;
        config = {
          italic-text = "always";
        };
        extraPackages = with pkgs.bat-extras; [
          batman
          batdiff
          batwatch
        ];
      };

      home.shellAliases = {
        "cat" = "bat --style header-filename --paging never";
        "man" = "batman";
        "watch" = "batwatch";
      };
    }

    # direnv
    {
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };
    }

    # eza
    {
      programs.eza = {
        enable = true;
        icons = "auto";
      };

      home.shellAliases = {
        ls = lib.mkForce "eza --group-directories-first";
        l = lib.mkForce "eza --long --header --group-directories-first";
        ll = lib.mkForce "eza -long --header --git --group-directories-first";
        la = lib.mkForce "eza --long --header --all --git --group-directories-first";
        lt = "eza --tree";
        tree = "eza --tree";
      };
    }

    # fastfetch
    {
      programs.fastfetch = {
        enable = true;
        package = pkgs.fastfetchMinimal;
      };
    }

    {programs.fd.enable = true;}

    # fzf
    {
      programs.fzf = let
        bat = lib.getExe pkgs.bat;
        eza = lib.getExe pkgs.eza;
        fd = lib.getExe pkgs.fd;
      in {
        enable = true;
        enableZshIntegration = true;

        defaultCommand = "${fd} --type f --strip-cwd-prefix --hidden --exclude .git";

        fileWidgetOptions = [
          "--multi"
          "--preview '${bat} --color=always --style=numbers --line-range=:500 {}'"
        ];
        fileWidgetCommand = ''
          ${fd} --type f --strip-cwd-prefix --hidden --exclude .git
        '';

        changeDirWidgetCommand = ''
          ${fd} --type d --strip-cwd-prefix --hidden --exclude .git
        '';
        changeDirWidgetOptions = [
          "--preview '${eza} --tree --color=always {} | head -200'"
        ];
      };

      programs.jq.enable = true;
      programs.ripgrep.enable = true;
      programs.tmux.enable = true;
    }

    # zoxide
    {
      programs.zoxide = {
        enable = true;
        enableZshIntegration = true;
        options = ["--cmd j"];
      };
    }
  ];
}
