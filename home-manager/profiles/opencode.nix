{
  pkgs,
  cfg,
  ...
}: let
  goalPlugin = "@nemowang2003/opencode-goal-plugin@0.1.25";
  pkg = pkgs.llm-agents.opencode;
in {
  programs.opencode = {
    enable = true;
    enableMcpIntegration = true;

    settings = {
      autoupdate = false;
      share = "disabled";
      permission = "allow";

      plugin = [goalPlugin];

      provider = {
        deepseek.options.chunkTimeout = 300000;
      };

      lsp = {
        ty = {
          command = ["ty" "server"];
          extensions = [".py"];
        };
      };
    };

    tui = {
      plugin = [goalPlugin];
    };

    package =
      if cfg.platform != "wsl"
      then pkg
      else
        # Work around WSL2 segfaults in opencode/bun binary output.
        # Drop this once upstream is fixed. See:
        # https://github.com/NixOS/nixpkgs/issues/520383
        # https://github.com/sethkrasnianski/nix-config/pull/4
        pkgs.runCommand pkg.name {
          nativeBuildInputs = [pkgs.patchelf];
          inherit (pkg) meta;
        }
        ''
          cp -a ${pkg} $out
          chmod -R u+w $out
          find $out -type f -exec sed -i "s|${pkg}|$out|g" {} +
          patchelf --set-interpreter "$(patchelf --print-interpreter "$out/bin/.opencode-wrapped")" "$out/bin/.opencode-wrapped"
        '';
  };

  home.sessionVariables = {
    "OPENCODE_DISABLE_LSP_DOWNLOAD" = "true";
    "OPENCODE_EXPERIMENTAL_LSP_TOOL" = "true";
  };

  xdg.configFile."opencode/plugins/notify-on-idle.js".text = ''
    export const NotifyOnIdlePlugin = async ({ $ }) => {
      let lastNotificationAt = 0

      return {
        event: async ({ event }) => {
          if (event.type !== "session.idle") return

          const now = Date.now()
          if (now - lastNotificationAt < 30_000) return
          lastNotificationAt = now

          try {
            if (process.platform === "darwin") {
              await $`osascript -e 'display notification "Agent finished working." with title "opencode"'`
              return
            }

            if (process.platform === "linux") {
              await $`sh -lc 'command -v notify-send >/dev/null 2>&1 && notify-send "opencode" "Agent finished working." || true'`
            }
          } catch {
            // Notifications are best-effort only.
          }
        },
      }
    }
  '';
}
