{pkgs, ...}: {
  my.lsp.servers.nixd = {
    package = pkgs.nixd;
    extensions = [".nix"];
    language = "nix";
  };

  home.packages = with pkgs; [
    alejandra
  ];
  programs = {
    helix.languages = {
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
