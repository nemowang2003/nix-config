{
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

    matchBlocks = {
      "github" = {
        match = ''host github.com exec "${nc} -z 127.0.0.1 7890"'';
        proxyCommand = "${nc} -X 5 -x 127.0.0.1:7890 %h %p";
        user = "git";
      };

      "china-server-tunnel" = {
        match = ''host cn-* exec "${nc} -z 127.0.0.1 7890"'';
        remoteForwards = [
          {
            bind.port = 7890;
            host.address = "127.0.0.1";
            host.port = 7890;
          }
        ];
      };

      "*" = {
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
  };
}
