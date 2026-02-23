{ config, pkgs, lib, ... }:

{
  programs.zsh = {
    enable = true;
    autocd = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    completionInit = "autoload -Uz compinit";
    defaultKeymap = "viins";

    shellGlobalAliases = {
      "..." = "../..";
      "...." = "../../..";
      "....." = "../../../..";
      "......" = "../../../../..";
    };

    shellAliases = {
      "-"="cd -";
      "1"="cd -1";
      "2"="cd -2";
      "3"="cd -3";
      "4"="cd -4";
      "5"="cd -5";
      "6"="cd -6";
      "7"="cd -7";
      "8"="cd -8";
      "9"="cd -9";
      l = "ls -lh";
      ll = "ls -lh";
      la = "ls -lAh";

      g = "git";
      ga = "git add";
      gb = "git branch";
      gba = "git branch --all";
      gco = "git checkout";
      gc = "git commit --verbose";
      gca = "git commit --verbose --all";
      gcan = "git commit --verbose --all --no-edit";
      "gca!" = "git commit --verbose --all --amend";
      "gcan!" = "git commit --verbose --all --amend --no-edit";
      gcn = "git commit --verbose --no=edit";
      "gcn!" = "git commit --verbose --no=edit --amend";
      gd = "git diff";
      gdca = "git diff --cached";
      gdcw = "git diff --cached --word-diff";
      gds = "git diff --staged";
      gdw = "git diff --word-diff";
      gfa = "git fetch --all --tags --prune --jobs=10";
      gl = "git pull";
      "gl!" = "git pull --autostash";
      glg = "git log --stat";
      glgg = "git log --graph";
      gp = "git push";
      gpf = "git push --force-with-lease --force-if-includes";
      "gpf!" = "git push --force";
      grb = "git rebase";
      grba = "git rebase --abort";
      grbc = "git rebase --continue";
      grbi = "git rebase --interactive";
      grf = "git reflog";
      gr = "git remote";
      grv = "git remote --verbose";
      gra = "git remote add";
      grrm = "git remote remove";
      grmv = "git remote rename";
      grset = "git remote set-url";
      # TODO: stash
      gst = "git status";
      gsw = "git switch";
      gswc = "git switch --create";

      uv = "noglob uv";
      uva = "uv add";
      uvi = "uv init";
      uvl = "uv lock";
      uvlr = "uv lock --refresh";
      uvlu = "uv lock --upgrade";
      uvr = "uv run";
      uvs = "uv sync";
      uvsr = "uv sync --refresh";
      uvsu = "uv sync --upgrade";
    } // lib.optionalAttrs pkgs.stdenv.isDarwin {
      ls = "ls -G";
    } // lib.optionalAttrs (!pkgs.stdenv.isDarwin) {
      
    };

    localVariables = {
      KEYTIMEOUT = 1;
    };

    sessionVariables = {
      LS_COLORS = "di=1;36:ln=35:so=32:pi=33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43";
    } // lib.optionalAttrs pkgs.stdenv.isDarwin {
      LSCOLORS = "Gxfxcxdxbxegedabagacad";
    } // lib.optionalAttrs (!pkgs.stdenv.isDarwin) {

    };

    history = {
      extended = true;
      append = true;
      share = true;
      expireDuplicatesFirst = true;
      ignoreDups = true;
      ignoreSpace = true;
    };

    historySubstringSearch = {
      enable = true;
      searchUpKey = [
        "^[[A"
        "\${terminfo[kcuu1]}"
      ];
      searchDownKey = [
        "^[[B"
        "\${terminfo[kcud1]}"
      ];
    };

    setOptions = [
      "ALWAYS_TO_END"
      "AUTO_PUSHD"
      "COMPLETE_IN_WORD"
      "HIST_VERIFY"
      "INTERACTIVE_COMMENTS"
      "LONG_LIST_JOBS"
      "PUSHD_IGNORE_DUPS"
      "PUSHD_MINUS"
      "PROMPT_SUBST"      
    ];

    initContent = lib.mkMerge[
      (lib.mkBefore ''
        if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
          source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
        fi
      '')
      (lib.mkAfter ''
        bindkey "^?" backward-delete-char

        function hx-select-line() {
          zle vi-beginning-of-line
          zle visual-line-mode
        }
        zle -N hx-select-line

        bindkey -M vicmd "w" vi-forward-word
        bindkey -M vicmd "d" vi-delete-char
        bindkey -M vicmd "x" hx-select-line
        bindkey -M visual "d" vi-delete                 

        zmodload -i zsh/complist

        zstyle ':completion:*:*:*:*:*' menu select
        zstyle ':completion:*' special-dirs true
        zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"
        zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#) ([0-9a-z-]#)*=01;34=0=01'

        zstyle ':completion:*' matcher-list 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' 'r:|=*' 'l:|=* r:|=*'

        zstyle ':completion:*' use-cache yes
        zstyle ':completion:*' cache-path "''${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"

        zstyle ':completion:*:*:*:users' ignored-patterns ${if pkgs.stdenv.isDarwin then "'_*'" else '' \
                adm amanda apache at avahi avahi-autoipd beaglidx bin cacti canna \
                clamav daemon dbus distcache dnsmasq dovecot fax ftp games gdm \
                gkrellmd gopher hacluster haldaemon halt hsqldb ident junkbust kdm \
                ldap lp mail mailman mailnull man messagebus mldonkey mysql nagios \
                named netdump news nfsnobody nobody nscd ntp nut nx obsrun openvpn \
                operator pcap polkitd postfix postgres privoxy pulse pvm quagga radvd \
                rpc rpcuser rpm rtkit scard shutdown squid sshd statd svn sync tftp \
                usbmux uucp vcsa wwwrun xfs '_*'
              ''}

        source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
        source ${./p10k.zsh}
      '')
    ];
  };
}
