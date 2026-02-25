{ pkgs, lib, ... }:

{
  programs.zsh = {
    enable = true;
    autocd = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    completionInit = "autoload -Uz compinit && compinit";
    defaultKeymap = "viins";

    shellGlobalAliases = {
      "..." = "../..";
      "...." = "../../..";
      "....." = "../../../..";
      "......" = "../../../../..";
    };

    shellAliases = {
      "1" = "cd -1";
      "2" = "cd -2";
      "3" = "cd -3";
      "4" = "cd -4";
      "5" = "cd -5";
      "6" = "cd -6";
      "7" = "cd -7";
      "8" = "cd -8";
      "9" = "cd -9";
      d = "dirs -v";
    };

    localVariables = {
      KEYTIMEOUT = 1;
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
