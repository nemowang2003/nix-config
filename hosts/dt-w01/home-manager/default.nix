{
  pkgs,
  lib,
  ...
}: {
  imports = [./codex];

  home.stateVersion = "25.11";

  systemd.user = {
    services.skyland-auto-sign = {
      Unit = {
        Description = "Skyland Auto Sign Service";
        After = ["network-online.target"];
      };
      Service = {
        Type = "oneshot";
        WorkingDirectory = "%h/skyland-auto-sign";
        ExecStart = "${lib.getExe pkgs.uv} run --python ${lib.getExe pkgs.python314} src/main.py";
      };
      Install.WantedBy = ["default.target"];
    };
    timers.skyland-auto-sign = {
      Unit.Description = "Run Skyland Auto Sign daily";
      Timer = {
        OnCalendar = "*-*-* 00:00:00";
        Persistent = true;
        Unit = "skyland-auto-sign.service";
      };
      Install.WantedBy = ["timers.target"];
    };
  };
}
