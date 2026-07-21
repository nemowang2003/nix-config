{pkgs, ...}: {
  home.packages = with pkgs; [
    nixd
    alejandra
  ];
  programs = {
    helix.languages = {
      language-server.nixd.command = "nixd";
      language = [
        {
          name = "nix";
          auto-format = true;
          language-servers = ["nixd"];
          formatter.command = "alejandra";
        }
      ];
    };
  };
}
