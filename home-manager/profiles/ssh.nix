{
  self,
  config,
  lib,
  pkgs,
  ...
}: let
  nc = lib.getExe pkgs.netcat;
  public-hosts = lib.filterAttrs (_: cfg: cfg.public) self.hosts;
  mk-public-block = hostname: cfg: let
    ip = self.public-ips.${hostname} or null;
    proxy-extra =
      if cfg.domestic
      then {remoteForward = "7890 127.0.0.1:7890";}
      else {proxyCommand = "${nc} -X 5 -x 127.0.0.1:7890 %h %p";};
  in
    lib.optionalAttrs (ip != null) {
      "${hostname}" = {
        header = "Host ${hostname}";
        hostName = ip;
        hostKeyAlias = hostname;
        user = cfg.user;
      };
      "${hostname}-proxy" =
        {
          header = ''Match host ${hostname} exec "${nc} -z 127.0.0.1 7890"'';
        }
        // proxy-extra;
    };
in {
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    # Every public host always resolves to its public IP (read from the
    # devshell-generated .public-ips.json). When the local proxy is up,
    # overseas hosts additionally route through it and domestic hosts get a
    # reverse tunnel for it; when it is down the direct IP block still applies.
    settings =
      {
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
      }
      // lib.concatMapAttrs mk-public-block public-hosts;
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
