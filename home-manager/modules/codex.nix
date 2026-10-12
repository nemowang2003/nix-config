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
  # MCP renderer for the isolated TCA home, while keeping both configs mutable.

  mirrored-codex-options = self.lib.options.mirror-options {
    inherit upstream;
    excluded = ["enable" "custom-instructions"];
  };
in {
  imports = [
    (lib.mkRenamedOptionModule
      ["my" "codex" "custom-instructions"]
      ["my" "codex" "context"])
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

      tca-hooks = lib.mkOption {
        type = upstream.hooks.type;
        default = cfg.hooks;
        description = "Hooks installed in ~/.codex-tca/hooks.json. Defaults to the shared hooks; override to identify TCA notifications separately.";
      };

      tca-settings = lib.mkOption {
        type = (pkgs.formats.toml {}).type;
        default = {};
        description = "Provider-specific settings merged with shared settings into ~/.codex-tca/config.toml. Runtime model choices are preserved when not declared here.";
      };

      removed-paths = lib.mkOption {
        type = lib.types.listOf (lib.types.listOf lib.types.str);
        default = [];
        description = "Obsolete TOML paths removed from the official Codex config during activation.";
      };

      tca-removed-paths = lib.mkOption {
        type = lib.types.listOf (lib.types.listOf lib.types.str);
        default = [];
        description = "Obsolete or official-only TOML paths removed from the TCA Codex config during activation.";
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

    tca-target = ".codex-tca";
    tca-home = "${config.home.homeDirectory}/${tca-target}";
    tca-config-path = "${tca-home}/config.toml";
    codex-lib = import "${inputs.home-manager}/modules/programs/codex/lib.nix" {inherit lib pkgs;};
    # Copy individual declarative assets, never mutable directories or auth/state.
    common-files =
      ["AGENTS.md"]
      ++ lib.optional (cfg.contextOverride != null) "AGENTS.override.md"
      ++ map (name: "skills/${name}") (lib.attrNames (codex-lib.mkSkillSources cfg.skills))
      ++ map (name: "rules/${name}.rules") (lib.attrNames cfg.rules);
    tca-common-files = lib.genAttrs common-files (name: let
      file = config.home.file."${config-dir}/${name}";
    in {
      inherit (file) source recursive;
    });
    tca-source = pkgs.runCommand "codex-tca-config.toml" {} ''
      ${lib.getExe pkgs.yj} -tj < ${config-source} > common.json
      ${lib.getExe pkgs.yj} -tj < ${toml-format.generate "codex-tca-settings" cfg.tca-settings} > tca.json
      ${lib.getExe pkgs.jq} -s \
        '.[0] * .[1] | delpaths(${builtins.toJSON cfg.tca-removed-paths})' \
        common.json tca.json | ${lib.getExe pkgs.yj} -jt > "$out"
    '';
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
    codex-tca = pkgs.writeShellScriptBin "codex-tca" ''
      export CODEX_HOME=${lib.escapeShellArg tca-home}
      exec ${lib.getExe cfg.package} "$@"
    '';

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
      my.codex.context = lib.mkIf (context-chunks != []) (
        lib.concatStringsSep "\n\n" context-chunks
      );

      programs.codex =
        {
          enable = true;
        }
        // removeAttrs cfg ["enable" "custom-instructions" "contexts" "removed-paths" "tca-settings" "tca-hooks" "tca-removed-paths" "profile-removed-paths"]
        // {package = codex-openai;};

      # Keep Codex config mutable because Codex writes trust/bookkeeping state to
      # config.toml at runtime. See:
      # https://github.com/nix-community/home-manager/issues/9397
      programs.zsh.initContent = lib.mkAfter ''
        compdef _codex codex-tca
      '';

      home = {
        packages = [codex-tca];
        sessionVariables = {
          CODEX_HOME = lib.mkForce official-home;
          CODEX_NOTIFY_HOMES = "${official-home}:${tca-home}";
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
          // lib.mapAttrs' (name: file: lib.nameValuePair "${tca-target}/${name}" file) tca-common-files
          // lib.optionalAttrs (cfg.tca-hooks != {}) {
            "${tca-target}/hooks.json".source =
              if lib.hm.strings.isPathLike cfg.tca-hooks
              then
                (
                  if lib.isPath cfg.tca-hooks && lib.pathIsDirectory cfg.tca-hooks
                  then cfg.tca-hooks + "/hooks.json"
                  else cfg.tca-hooks
                )
              else (pkgs.formats.json {}).generate "codex-tca-hooks" {hooks = cfg.tca-hooks;};
          }
          // lib.optionalAttrs (lib.isPath cfg.tca-hooks && lib.pathIsDirectory cfg.tca-hooks) {
            "${tca-target}/hooks" = {
              source = cfg.tca-hooks;
              recursive = true;
            };
          };

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
          // {
            mutable-codex-tca-config = lib.hm.dag.entryAfter ["writeBoundary"] (
              self.lib.mutable-config.mk-mutable-merge {
                inherit pkgs;
                format = "toml";
                path = tca-config-path;
                source = tca-source;
                removed-paths = cfg.tca-removed-paths;
              }
            );
          };
      };
    };
}
