{
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption types;

  enabledLanguages = lib.filterAttrs (_: language: language.enable) config.my.languages;
  referencedLspServers = lib.unique (lib.concatMap (language: language.lsp) (lib.attrValues enabledLanguages));
  helixLanguages =
    lib.filterAttrs
    (_: language: language.helix.enable)
    enabledLanguages;
  helixLanguageValues = lib.attrValues helixLanguages;
  helixLspNames = lib.unique (lib.concatMap (language: language.lsp) helixLanguageValues);

  lspServer = name: config.my.lsp.servers.${name};
  lspCommand = server:
    if server.command != null
    then server.command
    else lib.getExe server.package;
  mkHelixLanguage = language:
    {
      name = language.helix.name;
      language-servers = language.lsp;
    }
    // lib.optionalAttrs (language.roots != []) {
      roots = language.roots;
    }
    // lib.optionalAttrs language.helix.autoFormat {
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

        helix.autoFormat = mkOption {
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
    referencedLspServers;

  config.programs.helix.languages = lib.mkIf config.programs.helix.enable {
    language = map mkHelixLanguage helixLanguageValues;
    language-server =
      lib.genAttrs helixLspNames
      (name: let
        server = lspServer name;
      in
        {
          command = lspCommand server;
        }
        // lib.optionalAttrs (server.args != []) {
          args = server.args;
        });
  };
}
