{
  self,
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkOption types;

  declared = lib.filterAttrs (_: account: account.enable) config.my.twofa;

  mkAccountSecret = name: field: file-name: {
    name = "2fa/${name}/${file-name}";
    value = {
      sopsFile = self.sops.text.twofa-file;
      key = "${name}/${field}";
      path = "${config.xdg.configHome}/2fa/${name}/${file-name}";
      mode = "0600";
    };
  };
in {
  options.my.twofa = mkOption {
    type = types.attrsOf (types.submodule ({name, ...}: {
      options = {
        enable = mkEnableOption "2FA files for ${name}";

        recoveryCodes = mkOption {
          type = types.bool;
          default = false;
          description = "Whether recovery codes are stored for this account.";
        };
      };
    }));
    default = {};
    description = ''
      Registry of 2FA secrets. Each entry is backed by the trusted sops file
      secrets/text/2fa.yaml:

      ```yaml
      github:
        key: JBSWY3DPEHPK3PXP
        recovery_codes: |
          1234-5678
          9012-3456
      ```

      and is materialized to
      {file}`~/.config/2fa/<name>/key` and, when enabled,
      {file}`~/.config/2fa/<name>/recovery-codes`, both mode 0600.
    '';
  };

  config.sops.secrets =
    builtins.listToAttrs
    (lib.concatLists
      (lib.mapAttrsToList
        (name: account:
          [(mkAccountSecret name "key" "key")]
          ++ lib.optionals account.recoveryCodes [
            (mkAccountSecret name "recovery_codes" "recovery-codes")
          ])
        declared));
}
