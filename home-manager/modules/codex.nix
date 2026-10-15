{
  self,
  config,
  lib,
  options,
  inputs,
  pkgs,
  ...
}: let
  cfg = config.my.codex;
  upstream = options.programs.codex;

  # Upstream renders the official home. Reuse its common file sources and
  # MCP renderer for additional isolated homes, keeping all configs mutable.

  mirrored-codex-options = self.lib.options.mirror-options {
    inherit upstream;
    excluded = ["enable" "custom-instructions"];
  };
in {
  imports = [
    (lib.mkRenamedOptionModule
      ["my" "codex" "custom-instructions"]
      ["my" "codex" "context"])
    (lib.mkRenamedOptionModule ["my" "codex" "tca-settings"] ["my" "codex" "homes" "tca" "settings"])
    (lib.mkRenamedOptionModule ["my" "codex" "tca-hooks"] ["my" "codex" "homes" "tca" "hooks"])
    (lib.mkRenamedOptionModule ["my" "codex" "tca-removed-paths"] ["my" "codex" "homes" "tca" "removed-paths"])
  ];

  options.my.codex =
    {
      enable = lib.mkEnableOption "mutable Codex configuration";

      contexts = lib.mkOption {
        type = lib.types.listOf (lib.types.either lib.types.lines lib.types.path);
        default = [];
        description = ''
          Chunks that are concatenated into Codex's global {file}`AGENTS.md`,
          in priority order. Each element is either inline content or a path
          to a file.

          Host modules can combine {command}`lib.mkBefore`,
          {command}`lib.mkAfter` and {command}`lib.mkForce` with
          {command}`lib.mkMerge` to add host-specific sections around shared
          content or replace every chunk. The assembled result is passed to
          {option}`programs.codex.context`; setting
          {option}`my.codex.context` directly (with {command}`lib.mkForce`)
          remains a final override.
        '';
        example = lib.literalExpression ''
          # hosts/<hostname>/home-manager/default.nix
          {
            my.codex.contexts = lib.mkMerge [
              (lib.mkBefore [
                '''
                  # Host-specific instructions
                '''
              ])
              (lib.mkAfter [
                '''
                  # More host-specific instructions
                '''
              ])
            ];
          }
        '';
      };

      homes = lib.mkOption {
        default = {};
        description = "Additional isolated homes. Each name creates codex-<name> using ~/.codex-<name>, inheriting declarative config, instructions, skills, rules, profiles, and completions.";
        type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
          options = {
            settings = lib.mkOption {
              type = (pkgs.formats.toml {}).type;
              default = {};
              description = "Settings merged over the shared declarative config, independently of runtime settings in other homes.";
            };
            hooks = lib.mkOption {
              type = upstream.hooks.type;
              default = cfg.hooks-for-home "${config.home.homeDirectory}/.codex-${name}";
              description = "Hooks for this home; defaults to hooks-for-home applied to its absolute path.";
            };
            removed-paths = lib.mkOption {
              type = lib.types.listOf (lib.types.listOf lib.types.str);
              default = cfg.removed-paths;
              description = "TOML paths removed after merging shared and home-specific settings.";
            };
          };
        }));
      };

      hooks-for-home = lib.mkOption {
        type = lib.types.functionTo upstream.hooks.type;
        default = _: cfg.hooks;
        description = "Build hooks for an additional home's absolute path. Defaults to the shared hooks.";
      };

      home-directories = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
        description = "Absolute paths of the official and additional homes, for notification and relay consumers.";
      };

      removed-paths = lib.mkOption {
        type = lib.types.listOf (lib.types.listOf lib.types.str);
        default = [];
        description = "Obsolete TOML paths removed from the official Codex config during activation; inherited by additional homes unless overridden.";
      };

      profile-removed-paths = lib.mkOption {
        type = lib.types.attrsOf (lib.types.listOf (lib.types.listOf lib.types.str));
        default = {};
        description = "Obsolete TOML paths removed from mutable Codex profile files during activation.";
      };
    }
    // mirrored-codex-options;

  config = let
    render-context-chunk = chunk:
      if builtins.isPath chunk
      then builtins.readFile chunk
      else chunk;

    context-chunks =
      lib.filter
      (chunk: chunk != "")
      (map (chunk: lib.trim (render-context-chunk chunk)) cfg.contexts);

    use-xdg-directories = config.home.preferXdgDirectories;
    xdg-config-home = lib.removePrefix config.home.homeDirectory config.xdg.configHome;
    config-dir =
      if use-xdg-directories
      then "${xdg-config-home}/codex"
      else ".codex";
    official-target = ".codex-openai";
    official-home = "${config.home.homeDirectory}/${official-target}";
    config-target = "${config-dir}/config.toml";
    config-path = "${official-home}/config.toml";
    has-config-source = lib.hasAttrByPath [config-target "source"] config.home.file;
    config-source = lib.getAttrFromPath [config-target "source"] config.home.file;

    codex-lib = import "${inputs.home-manager}/modules/programs/codex/lib.nix" {inherit lib pkgs;};
    # Copy individual declarative assets, never mutable directories or auth/state.
    common-files =
      ["AGENTS.md"]
      ++ lib.optional (cfg.contextOverride != null) "AGENTS.override.md"
      ++ map (name: "skills/${name}") (lib.attrNames (codex-lib.mkSkillSources cfg.skills))
      ++ map (name: "rules/${name}.rules") (lib.attrNames cfg.rules);
    common-sources = lib.genAttrs common-files (name: let
      file = config.home.file."${config-dir}/${name}";
    in {
      inherit (file) source recursive;
    });
    extra-homes =
      lib.mapAttrs (name: home: let
        target = ".codex-${name}";
        path = "${config.home.homeDirectory}/${target}";
      in {
        inherit target path;
        inherit (home) hooks removed-paths;
        package = pkgs.writeShellScriptBin "codex-${name}" ''
          export CODEX_HOME=${lib.escapeShellArg path}
          exec ${lib.getExe cfg.package} "$@"
        '';
        source = pkgs.runCommand "codex-${name}-config.toml" {} ''
          ${lib.getExe pkgs.yj} -tj < ${config-source} > common.json
          ${lib.getExe pkgs.yj} -tj < ${toml-format.generate "codex-${name}-settings" home.settings} > home.json
          ${lib.getExe pkgs.jq} -s \
            '.[0] * .[1] | delpaths(${builtins.toJSON home.removed-paths})' \
            common.json home.json | ${lib.getExe pkgs.yj} -jt > "$out"
        '';
      })
      cfg.homes;
    codex-openai = pkgs.symlinkJoin {
      name = "codex-openai-${lib.getVersion cfg.package}";
      paths = [cfg.package];
      meta = cfg.package.meta // {mainProgram = "codex";};
      postBuild = ''
        rm "$out/bin/codex"
        cat > "$out/bin/codex" <<'SCRIPT'
        #!${pkgs.runtimeShell}
        export CODEX_HOME=${lib.escapeShellArg official-home}
        exec ${lib.getExe cfg.package} "$@"
        SCRIPT
        chmod +x "$out/bin/codex"
      '';
    };
    official-files =
      common-files
      ++ ["config.toml"]
      ++ lib.optional (cfg.hooks != {}) "hooks.json"
      ++ lib.optional (lib.isPath cfg.hooks && lib.pathIsDirectory cfg.hooks) "hooks"
      ++ map (name: "${name}.config.toml") (lib.attrNames cfg.profiles);
    # Codex writes to its profile files too, so they get the same mutable
    # treatment as config.toml: Home Manager only builds the TOML, and the
    # activation merge below installs it over whatever is on disk.
    # Names come from the option rather than from `config.home.file`, because
    # this module also defines entries there and reading the whole set back
    # would recurse.
    toml-format = pkgs.formats.toml {};
    profile-files = builtins.listToAttrs (
      map
      (name: let
        target = "${config-dir}/${name}.config.toml";
      in
        lib.nameValuePair name {
          inherit target;
          path = "${official-home}/${name}.config.toml";
          source = toml-format.generate "codex-${name}-config" cfg.profiles.${name};
        })
      (lib.attrNames cfg.profiles)
    );

    mk-mutable-merge = {
      path,
      source,
      removed-paths ? [],
    }:
      lib.hm.dag.entryAfter ["writeBoundary"] (
        self.lib.mutable-config.mk-mutable-merge {
          inherit pkgs path source removed-paths;
          format = "toml";
        }
      );
  in
    lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = lib.all (name: name != "openai" && builtins.match "[a-z0-9][a-z0-9-]*" name != null) (lib.attrNames cfg.homes);
          message = "my.codex.homes names must use lowercase letters, digits or hyphens, and cannot be openai (reserved for codex).";
        }
      ];

      my.codex.home-directories = [official-home] ++ map (home: home.path) (lib.attrValues extra-homes);

      my.codex.context = lib.mkIf (context-chunks != []) (
        lib.concatStringsSep "\n\n" context-chunks
      );

      programs.codex =
        {
          enable = true;
        }
        // lib.getAttrs (lib.attrNames mirrored-codex-options) cfg
        // {package = codex-openai;};

      # Keep Codex config mutable because Codex writes trust/bookkeeping state to
      # config.toml at runtime. See:
      # https://github.com/nix-community/home-manager/issues/9397
      programs.zsh.initContent = lib.mkAfter (lib.concatMapStringsSep "\n" (name: "compdef _codex codex-${name}") (lib.attrNames extra-homes));

      home = {
        packages = map (home: home.package) (lib.attrValues extra-homes);
        sessionVariables = {
          CODEX_HOME = lib.mkForce official-home;
          CODEX_NOTIFY_HOMES = lib.concatStringsSep ":" cfg.home-directories;
        };
        file =
          {
            ${config-target}.enable = lib.mkForce false;
          }
          // lib.listToAttrs (map (name:
            lib.nameValuePair "${config-dir}/${name}" {
              target = "${official-target}/${name}";
            })
          official-files)
          // lib.mapAttrs'
          (_: profile: lib.nameValuePair profile.target {enable = lib.mkForce false;})
          profile-files
          // lib.concatMapAttrs (name: home:
            lib.mapAttrs' (file-name: file: lib.nameValuePair "${home.target}/${file-name}" file) common-sources
            // lib.optionalAttrs (home.hooks != {}) {
              "${home.target}/hooks.json".source =
                if lib.hm.strings.isPathLike home.hooks
                then
                  (
                    if lib.isPath home.hooks && lib.pathIsDirectory home.hooks
                    then home.hooks + "/hooks.json"
                    else home.hooks
                  )
                else (pkgs.formats.json {}).generate "codex-${name}-hooks" {hooks = home.hooks;};
            }
            // lib.optionalAttrs (lib.isPath home.hooks && lib.pathIsDirectory home.hooks) {
              "${home.target}/hooks" = {
                source = home.hooks;
                recursive = true;
              };
            })
          extra-homes;

        activation =
          lib.mapAttrs'
          (
            name: profile:
              lib.nameValuePair "mutable-codex-profile-${name}" (mk-mutable-merge {
                inherit (profile) path source;
                removed-paths = cfg.profile-removed-paths.${name} or [];
              })
          )
          profile-files
          // lib.optionalAttrs has-config-source {
            mutable-codex-config = mk-mutable-merge {
              path = config-path;
              source = config-source;
              removed-paths = cfg.removed-paths;
            };
          }
          // lib.concatMapAttrs (name: home:
            {
              "mutable-codex-${name}-config" = mk-mutable-merge {
                path = "${home.path}/config.toml";
                inherit (home) source removed-paths;
              };
            }
            // lib.mapAttrs' (profile-name: profile:
              lib.nameValuePair "mutable-codex-${name}-profile-${profile-name}" (mk-mutable-merge {
                path = "${home.path}/${profile-name}.config.toml";
                inherit (profile) source;
                removed-paths = cfg.profile-removed-paths.${profile-name} or [];
              }))
            profile-files)
          extra-homes;
      };
    };
}
