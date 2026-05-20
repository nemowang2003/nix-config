{
  lib,
  pkgs,
  cfg,
  ...
}: let
  uv = lib.getExe pkgs.uv;
in {
  systemd = {
    services.skyland-auto-sign = {
      description = "Skyland Auto Sign Service";
      after = ["network-online.target"];
      wants = ["network-online.target"];

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        WorkingDirectory = "/home/${cfg.user}/skyland-auto-sign";
        ExecStart = "${uv} run src/main.py";
      };
    };

    timers.skyland-auto-sign = {
      description = "Run Skyland Auto Sign daily";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*-*-* 00:00:00";
        Persistent = true;
        Unit = "skyland-auto-sign.service";
      };
    };
  };

  system.stateVersion = "25.05";
}
