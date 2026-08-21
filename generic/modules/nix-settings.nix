{
  config,
  hostname,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption types;

  nix-cfg = config.nix;
  setting-value-type = types.oneOf [
    types.bool
    types.int
    types.str
    types.path
    (types.listOf (types.oneOf [types.str types.path]))
  ];
  render-value = value:
    if builtins.isBool value
    then lib.boolToString value
    else if builtins.isList value
    then lib.concatMapStringsSep " " toString value
    else toString value;
  nix-config = pkgs.writeText "nix-${hostname}.conf" (lib.generators.toKeyValue {
      mkKeyValue = key: value: "${key} = ${render-value value}";
    }
    nix-cfg.settings);
  nix-config-target =
    if nix-cfg.determinate
    then "/etc/nix/nix.custom.conf"
    else "/etc/nix/nix.conf";
in {
  options = {
    nix = {
      determinate = mkOption {
        type = types.bool;
        default = false;
        description = "Whether this host uses Determinate Nix.";
      };

      settings = mkOption {
        type = types.attrsOf setting-value-type;
        default = {};
        description = "System-wide Nix daemon settings.";
      };
    };

    system.build.activationPackage = mkOption {
      type = types.package;
      readOnly = true;
      internal = true;
      description = "Root activation package for a generic Linux host.";
    };
  };

  config.system.build.activationPackage = pkgs.writeShellApplication {
    name = "generic-system-activate";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      if (( EUID != 0 )); then
        echo "generic-system-activate must run as root" >&2
        exit 1
      fi

      nix_config_source=${lib.escapeShellArg nix-config}
      nix_config_target=${lib.escapeShellArg nix-config-target}

      systemctl_bin="$(command -v systemctl || true)"
      if [[ -z "$systemctl_bin" ]]; then
        echo "systemctl is required to restart nix-daemon.service" >&2
        exit 1
      fi

      install --directory --mode 755 "$(dirname "$nix_config_target")"
      install --mode 644 "$nix_config_source" "$nix_config_target"
      "$systemctl_bin" restart nix-daemon.service
    '';
  };
}
