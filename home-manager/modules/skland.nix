{
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption types;

  cfg = config.my.skland;
  defaultStateDir = "${config.xdg.stateHome}/skland-auto-sign";

  accountType = types.submodule ({name, ...}: {
    options = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to include this Skland account.";
      };

      phoneSecret = mkOption {
        type = types.str;
        default = "SKLAND_${lib.toUpper name}_PHONE";
        description = "Secret key containing the account phone number.";
      };

      passwordSecret = mkOption {
        type = types.str;
        default = "SKLAND_${lib.toUpper name}_PASSWORD";
        description = "Secret key containing the account password.";
      };

      secretGroup = mkOption {
        type = types.enum ["common" "trusted" "host"];
        default = "host";
        description = "Recipient group backing this account's secrets.";
      };
    };
  });
in {
  options.my.skland = {
    enable = lib.mkEnableOption "Skland auto sign user timer";

    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = "Package that provides the skland-auto-sign executable.";
    };

    command = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Command used to run skland-auto-sign. Defaults to the package executable once implemented.";
    };

    args = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional command arguments passed to skland-auto-sign.";
    };

    onCalendar = mkOption {
      type = types.str;
      default = "*-*-* 00:00:00";
      description = "systemd timer calendar expression for the daily sign job.";
    };

    persistent = mkOption {
      type = types.bool;
      default = true;
      description = "Whether missed timer runs should be triggered when the user manager starts again.";
    };

    randomizedDelaySec = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "30min";
      description = "Optional systemd timer randomized delay.";
    };

    stateDir = mkOption {
      type = types.str;
      default = defaultStateDir;
      description = "Writable state directory for Skland credentials, refreshed tokens, and logs.";
    };

    credentialFile = mkOption {
      type = types.str;
      default = "${defaultStateDir}/credential.json";
      description = "Writable credential file read and updated by skland-auto-sign.";
    };

    accounts = mkOption {
      type = types.attrsOf accountType;
      default = {};
      description = "Declarative Skland accounts whose seed credentials should be rendered from secrets.";
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = [
      "my.skland is a skeleton module. Service, timer, secret rendering, and credential merge are TODO."
    ];

    # TODO: assert that this module is only enabled on Linux with a user systemd manager.
    # TODO: declare my.env-secrets entries for cfg.accounts.
    # TODO: render a read-only seed credentials file from sops-managed secrets.
    # TODO: create cfg.stateDir and merge seed credentials into cfg.credentialFile before each run.
    # TODO: define systemd.user.services.skland-auto-sign as a oneshot user service.
    # TODO: define systemd.user.timers.skland-auto-sign with cfg.onCalendar and cfg.persistent.
  };
}
