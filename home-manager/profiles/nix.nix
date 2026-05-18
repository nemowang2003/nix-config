{
  pkgs,
  lib,
  ...
}: {
  programs = {
    helix.languages = {
      language-server.nixd.command = lib.getExe pkgs.nixd;
      language = [
        {
          name = "nix";
          auto-format = true;
          language-servers = ["nixd"];
          formatter = {
            command = lib.getExe pkgs.alejandra;
          };
        }
      ];
    };
  };
}
