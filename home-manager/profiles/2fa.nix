{
  self,
  config,
  pkgs,
  lib,
  cfg,
  ...
}: let
  # Only inspect encrypted JSON keys; plaintext never enters Nix evaluation.
  secret-tree = builtins.removeAttrs (builtins.fromJSON (builtins.readFile self.sops.text.twofa-file)) ["sops"];
  file-paths = prefix: tree:
    lib.concatLists (lib.mapAttrsToList (name: value: let
      path = prefix ++ [name];
    in
      if builtins.isAttrs value
      then file-paths path value
      else [(lib.concatStringsSep "/" path)])
    tree);
in {
  config = lib.mkIf cfg.trusted {
    home.packages = [self.packages.${pkgs.stdenv.hostPlatform.system}."2fa"];
    my.secrets.files = builtins.listToAttrs (map (path: {
      name = "2fa/${path}";
      value = {
        scope = "trusted";
        file = "2fa.json";
        key = path;
        format = "json";
        path = "${config.xdg.configHome}/2fa/${path}";
        mode = "0600";
      };
    }) (file-paths [] secret-tree));
  };
}
