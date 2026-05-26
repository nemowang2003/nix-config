{
  self,
  config,
  lib,
  pkgs,
  ...
}: let
  nc = lib.getExe pkgs.netcat;
in {
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    settings = {
      "github" = {
        header = ''Match host github.com exec "${nc} -z 127.0.0.1 7890"'';
        proxyCommand = "${nc} -X 5 -x 127.0.0.1:7890 %h %p";
        user = "git";
      };

      "china-server-tunnel" = {
        header = ''Match host cn-* exec "${nc} -z 127.0.0.1 7890"'';
        remoteForward = "7890 127.0.0.1:7890";
      };

      "Host *" = {
        serverAliveInterval = 60;
        serverAliveCountMax = 3;
        controlMaster = "auto";
        controlPath = "${config.home.homeDirectory}/.ssh/sockets/%r@%h-%p";
        controlPersist = "10m";
      };
    };
  };

  home.activation = {
    createSshSocketDir = lib.hm.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD mkdir -m 700 -p $VERBOSE_ARG ${config.home.homeDirectory}/.ssh/sockets
    '';

    writeAuthorizedKeysFile = lib.hm.dag.entryAfter ["writeBoundary"] ''
      AUTH_FILE="${config.home.homeDirectory}/.ssh/authorized_keys"

      if [ -f "$AUTH_FILE" ] && [ ! -L "$AUTH_FILE" ]; then
        $DRY_RUN_CMD mv "$AUTH_FILE" "$AUTH_FILE.$HOME_MANAGER_BACKUP_EXT"
      fi

      $DRY_RUN_CMD echo "${lib.concatStringsSep "\n" self.userPubkeys}" > "$AUTH_FILE"
      $DRY_RUN_CMD chmod 600 "$AUTH_FILE"
    '';
  };
}
