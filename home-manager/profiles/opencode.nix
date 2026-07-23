{
  config,
  lib,
  pkgs,
  cfg,
  ...
}: let
  goalPlugin = "@nemowang2003/opencode-goal-plugin@0.1.25";
  pkg = pkgs.llm-agents.opencode;
  lspServers = lib.filterAttrs (_: server: server.enable && server.agent.enable && server.extensions != []) config.my.lsp.servers;
  lspCommand = server:
    if server.command != null
    then server.command
    else lib.getExe server.package;
in {
  my.env-secrets.OPENCODE_NOTIFY_URL.group = "common";

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

      lsp =
        lib.mapAttrs
        (_: server: {
          command = [(lspCommand server)] ++ server.args;
          inherit (server) extensions;
        })
        lspServers;
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
    export const NotifyOnIdlePlugin = async ({ client, $ }) => {
      const activeSessions = new Set()
      let lastNotificationAt = 0
      const notifyUrl = process.env.OPENCODE_NOTIFY_URL

      return {
        event: async ({ event }) => {
          if (event.type !== "session.status") return

          const { sessionID, status } = event.properties
          if (status.type === "busy" || status.type === "retry") {
            activeSessions.add(sessionID)
            return
          }

          if (status.type !== "idle") return
          if (!activeSessions.delete(sessionID)) return
          if (!notifyUrl) return

          const session = await client.session
            .get({ path: { id: sessionID } })
            .then((result) => result.data)
            .catch(() => undefined)
          if (!session || session.parentID) return

          const now = Date.now()
          if (now - lastNotificationAt < 30_000) return
          lastNotificationAt = now

          try {
            await $`${pkgs.curl}/bin/curl --fail --silent --show-error --max-time 10 ''${notifyUrl}`.quiet()
          } catch {
            // Notifications are best-effort only. Do not log the URL because it may contain a token.
            console.warn("[opencode] notification failed")
          }
        },
      }
    }
  '';
}
