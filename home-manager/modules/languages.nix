{
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption types;

  enabled-languages = lib.filterAttrs (_: language: language.enable) config.my.languages;
  referenced-lsp-servers = lib.unique (lib.concatMap (language: language.lsp) (lib.attrValues enabled-languages));
  helix-languages =
    lib.filterAttrs
    (_: language: language.helix.enable)
    enabled-languages;
  helix-language-values = lib.attrValues helix-languages;
  helix-lsp-names = lib.unique (lib.concatMap (language: language.lsp) helix-language-values);

  lsp-server = name: config.my.lsp.servers.${name};
  lsp-command = server:
    if server.command != null
    then server.command
    else lib.getExe server.package;
  mk-helix-language = language:
    {
      name = language.helix.name;
      language-servers = language.lsp;
    }
    // lib.optionalAttrs (language.roots != []) {
      roots = language.roots;
    }
    // lib.optionalAttrs language.helix.auto-format {
      auto-format = true;
    }
    // lib.optionalAttrs (language.formatter != null) {
      formatter = language.formatter;
    };
in {
  options.my.languages = mkOption {
    type = types.attrsOf (types.submodule ({name, ...}: {
      options = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to enable this language declaration.";
        };

        extensions = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "File extensions handled by this language.";
        };

        roots = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Root markers used by editors for this language.";
        };

        lsp = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "LSP server IDs from my.lsp.servers used for this language.";
        };

        formatter = mkOption {
          type = types.nullOr (types.submodule {
            options = {
              command = mkOption {
                type = types.str;
                description = "Formatter command.";
              };

              args = mkOption {
                type = types.listOf types.str;
                default = [];
                description = "Formatter command arguments.";
              };
            };
          });
          default = null;
          description = "Formatter used for this language.";
        };

        agent.enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether coding agents should consume this language's LSP servers.";
        };

        helix.enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether Helix should consume this language declaration.";
        };

        helix.name = mkOption {
          type = types.str;
          default = name;
          description = "Helix language name.";
        };

        helix.auto-format = mkOption {
          type = types.bool;
          default = false;
          description = "Whether Helix should format this language on save.";
        };
      };
    }));
    default = {};
    description = "Private registry of language-level LSP and formatter declarations.";
  };

  config.assertions =
    map (lsp: {
      assertion = lib.hasAttrByPath [lsp] config.my.lsp.servers && config.my.lsp.servers.${lsp}.enable;
      message = "my.languages references missing or disabled LSP server `${lsp}`.";
    })
    referenced-lsp-servers;

  config.programs.helix.languages = lib.mkIf config.programs.helix.enable {
    language = map mk-helix-language helix-language-values;
    language-server =
      lib.genAttrs helix-lsp-names
      (name: let
        server = lsp-server name;
      in
        {
          command = lsp-command server;
        }
        // lib.optionalAttrs (server.args != []) {
          args = server.args;
        });
  };
}
