{
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption types;

  enabledServers = lib.filterAttrs (_: server: server.enable) config.my.lsp.servers;
  pathServers = lib.filterAttrs (_: server: server.exposeToPath && server.package != null) enabledServers;
in {
  options.my.lsp.servers = mkOption {
    type = types.attrsOf (types.submodule ({name, ...}: {
      options = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to enable this LSP server declaration.";
        };

        package = mkOption {
          type = types.nullOr types.package;
          default = null;
          description = "Package that provides the LSP server binary.";
        };

        command = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Command used to start the LSP server. Defaults to lib.getExe package.";
        };

        args = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Arguments passed to the LSP server.";
        };

        exposeToPath = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to expose this LSP server package in PATH.";
        };

        agent.enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether coding agents should consume this LSP server.";
        };
      };
    }));
    default = {};
    description = "Shared LSP server declarations consumed by languages, editors, and coding agents.";
  };

  config = {
    assertions =
      lib.mapAttrsToList
      (name: server: {
        assertion = !server.enable || server.command != null || server.package != null;
        message = "my.lsp.servers.${name} must set either package or command.";
      })
      config.my.lsp.servers;

    home.packages = lib.unique (lib.mapAttrsToList (_: server: server.package) pathServers);
  };
}
