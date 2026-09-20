{
  self,
  config,
  lib,
  options,
  pkgs,
  ...
}: let
  cfg = config.my.codex;
  upstream = options.programs.codex;

  # A thin wrapper around Home Manager's programs.codex module.
  # Keep upstream responsible for MCP, plugins, profiles, skills, hooks, and
  # generated settings; only replace the main config symlink with a mutable
  # activation merge.

  # A null package has no detectable version, so match programs.codex and
  # assume latest behavior.
  at-least = version: cfg.package == null || lib.versionAtLeast (lib.getVersion cfg.package) version;
  is-toml-config = at-least "0.2.0";
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

    use-xdg-directories = config.home.preferXdgDirectories && is-toml-config;
    xdg-config-home = lib.removePrefix config.home.homeDirectory config.xdg.configHome;
    config-dir =
      if use-xdg-directories
      then "${xdg-config-home}/codex"
      else ".codex";
    config-file-name =
      if is-toml-config
      then "config.toml"
      else "config.yaml";
    config-target = "${config-dir}/${config-file-name}";
    config-path = "${config.home.homeDirectory}/${config-target}";
    has-config-source = lib.hasAttrByPath [config-target "source"] config.home.file;
    config-source = lib.getAttrFromPath [config-target "source"] config.home.file;

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
          path = "${config.home.homeDirectory}/${target}";
          source = toml-format.generate "codex-${name}-config" cfg.profiles.${name};
        })
      (lib.attrNames cfg.profiles)
    );

    format =
      if is-toml-config
      then "toml"
      else "yaml";

    mk-mutable-merge = {
      path,
      source,
      removed-paths ? [],
    }:
      lib.hm.dag.entryAfter ["writeBoundary"] (
        self.lib.mutable-config.mk-mutable-merge {
          inherit pkgs format path source removed-paths;
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
        // removeAttrs cfg ["enable" "custom-instructions" "contexts" "profile-removed-paths"];

      # Keep Codex config mutable because Codex writes trust/bookkeeping state to
      # config.toml at runtime. See:
      # https://github.com/nix-community/home-manager/issues/9397
      home = {
        file =
          {
            ${config-target}.enable = lib.mkForce false;
          }
          // lib.mapAttrs'
          (_: profile: lib.nameValuePair profile.target {enable = lib.mkForce false;})
          profile-files;

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
            };
          };
      };
    };
}
