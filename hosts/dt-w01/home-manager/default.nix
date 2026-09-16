{
  config,
  lib,
  pkgs,
  ...
}: let
  codex = lib.getExe pkgs.llm-agents.codex;
  codex-wecom-relay = lib.getExe pkgs.nemowang2003.codex-wecom-relay;
  user-home = config.home.homeDirectory;
in {
  home.stateVersion = "25.11";

  # Both daemons are user-wide rather than system-wide: they own ~/.codex
  # (trust state, thread db, control socket) and this user's state, and exist
  # to serve the same user's TUI. Linger is enabled in
  # hosts/dt-w01/nixos/default.nix, so they still start at boot and survive
  # WSL session teardown.
  systemd.user = {
    services.codex-app-server = {
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

    services.codex-wecom-relay = {
      Unit = {
        Description = "企业微信智能机器人长连接：投递 codex-notify 路由好的通知，并把用户回复注入本地 app-server";
        # Same scope, so the original ordering intent survives the move: the
        # relay connects lazily per turn and reports a failed injection on its
        # own, so a weak `Wants` is enough.
        After = ["codex-app-server.service"];
        Wants = ["codex-app-server.service"];
      };
      Service = {
        Type = "simple";
        WorkingDirectory = user-home;
        Environment = [
          "XDG_CACHE_HOME=${user-home}/.cache"
          "XDG_CONFIG_HOME=${user-home}/.config"
          "XDG_STATE_HOME=${user-home}/.local/state"
        ];
        # Credentials materialized by home-manager's secrets module; the path
        # matches my.secrets.files."wecom" in
        # home-manager/profiles/agents/codex/default.nix.
        ExecStart = "${codex-wecom-relay} --config ${config.xdg.configHome}/codex-wecom-relay/wecom.json";
        Restart = "on-failure";
        RestartSec = "5s";
        KillSignal = "SIGINT";
        TimeoutStopSec = "10s";
      };
      Install = {
        WantedBy = ["default.target"];
      };
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
