{
  lib,
  pkgs,
  ...
}: {
  home.stateVersion = "25.11";

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
