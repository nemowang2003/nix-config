{
  self,
  config,
  lib,
  pkgs,
  ...
}: let
  nc = lib.getExe pkgs.netcat;
  public-hosts = lib.filterAttrs (_: cfg: cfg.public) self.hosts;
  mk-public-secret = hostname: _: {
    name = "text/public-ips/${hostname}";
    value = {
      sopsFile = self.sops.text.public-ips-file;
      key = hostname;
      format = "yaml";
    };
  };
  mk-public-block = hostname: cfg: let
    ip = config.sops.placeholder."text/public-ips/${hostname}";
    route =
      if cfg.domestic
      then "    RemoteForward 7890 127.0.0.1:7890"
      else "    ProxyCommand ${nc} -X 5 -x 127.0.0.1:7890 %h %p";
  in ''
    Host ${hostname}
      HostName ${ip}
      HostKeyAlias ${hostname}
      User ${cfg.user}

    Match host ${hostname} exec "${nc} -z 127.0.0.1 7890"
    ${route}
  '';
in {
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    includes = ["${config.home.homeDirectory}/.ssh/config.d/*"];

    # When the local proxy is up, overseas hosts route through it and
    # domestic hosts get a reverse tunnel; when it is down the direct Host
    # block in the included fragment still applies.
    settings = {
      "github" = {
        header = ''Match host github.com exec "${nc} -z 127.0.0.1 7890"'';
        proxyCommand = "${nc} -X 5 -x 127.0.0.1:7890 %h %p";
        user = "git";
      };

      "Host *" = {
        serverAliveInterval = 60;
        serverAliveCountMax = 3;
        controlMaster = "auto";
        controlPath = "${config.home.homeDirectory}/.ssh/sockets/%r@%h-%p";
        controlPersist = "10m";
        updateHostKeys = false;
      };
    };
  };

  # One sops secret per public host (key = hostname). The template below is
  # rendered at activation time: placeholders become the decrypted IPs, so
  # the plaintext never enters the Nix store or the repository.
  sops.secrets = builtins.listToAttrs (lib.mapAttrsToList mk-public-secret public-hosts);

  sops.templates."ssh-public-hosts" = {
    path = "${config.home.homeDirectory}/.ssh/config.d/zz-public-hosts";
    mode = "0600";
    content =
      lib.concatStringsSep "\n"
      (lib.mapAttrsToList mk-public-block public-hosts);
  };

  home.activation = {
    create-ssh-socket-dir = lib.hm.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD mkdir -m 700 -p $VERBOSE_ARG ${config.home.homeDirectory}/.ssh/sockets
    '';

    write-authorized-keys-file = lib.hm.dag.entryAfter ["writeBoundary"] ''
      AUTH_FILE="${config.home.homeDirectory}/.ssh/authorized_keys"

      if [ -f "$AUTH_FILE" ] && [ ! -L "$AUTH_FILE" ]; then
        $DRY_RUN_CMD mv "$AUTH_FILE" "$AUTH_FILE.$HOME_MANAGER_BACKUP_EXT"
      fi

      $DRY_RUN_CMD echo "${lib.concatStringsSep "\n" self.user-pubkeys}" > "$AUTH_FILE"
      $DRY_RUN_CMD chmod 600 "$AUTH_FILE"
    '';
  };
}
