{
  config,
  lib,
  pkgs,
  ...
}: let
  codex = lib.getExe pkgs.llm-agents.codex;
  user-home = config.home.homeDirectory;
in {
  home.stateVersion = "25.11";

  # User-wide rather than system-wide: the daemon owns ~/.codex (trust state,
  # thread db) and exists to serve this user's TUI, so it can live under the
  # user manager and be driven with `systemctl --user`. Linger is enabled in
  # hosts/dt-w01/nixos/default.nix, so it still starts at boot.
  systemd.user.services.codex-app-server = {
    Unit = {
      Description = "Codex app-server daemon shared by the TUI and the reply relay";
    };
    Service = {
      Type = "simple";
      WorkingDirectory = user-home;
      # Materialized wholesale by home-manager's secrets module from
      # secrets/common/env; KEY=VALUE data is natively parsable by systemd.
      EnvironmentFile = "${config.xdg.configHome}/sops-nix/env/common";
      Environment = [
        "XDG_CACHE_HOME=${user-home}/.cache"
        "XDG_CONFIG_HOME=${user-home}/.config"
        "XDG_STATE_HOME=${user-home}/.local/state"
      ];
      ExecStartPre = "${lib.getExe' pkgs.coreutils "rm"} -f ${user-home}/.codex/app-server-control/app-server-control.sock";
      ExecStart = "${codex} app-server --listen unix://";
      Restart = "on-failure";
      RestartSec = "2s";
      KillSignal = "SIGINT";
      TimeoutStopSec = "30s";
      LimitNOFILE = "65536";
    };
    Install = {
      WantedBy = ["default.target"];
    };
  };

  my.codex.contexts = lib.mkAfter [
    ''
      ## dt-w01 host notes (NixOS WSL)

      本机是 NixOS WSL。需要调用 Windows 命令时使用 powershell.exe，不要用
      cmd.exe；并且不要给 powershell.exe 加 -NoProfile：用户 profile 会把输出
      编码设为 UTF-8，中文等非 ASCII 文本才能正确传递（输出被重定向时 profile
      里的交互式装饰会自动跳过）。
    ''
  ];

  # Runs as a *user* service so the interpreter and dependencies come from
  # the home-manager profile; the system-level variant could not see
  # ~/.nix-profile/bin. uv is still pinned to the store Python so PATH never
  # matters.
  systemd.user.services.skyland-auto-sign = {
    Unit = {
      Description = "Skyland Auto Sign Service";
      After = ["network-online.target"];
    };
    Service = {
      Type = "oneshot";
      WorkingDirectory = "%h/skyland-auto-sign";
      ExecStart = "${lib.getExe pkgs.uv} run --python ${lib.getExe pkgs.python314} src/main.py";
    };
    Install = {
      WantedBy = ["default.target"];
    };
  };

  systemd.user.timers.skyland-auto-sign = {
    Unit = {
      Description = "Run Skyland Auto Sign daily";
    };
    Timer = {
      OnCalendar = "*-*-* 00:00:00";
      Persistent = true;
      Unit = "skyland-auto-sign.service";
    };
    Install = {
      WantedBy = ["timers.target"];
    };
  };
}
