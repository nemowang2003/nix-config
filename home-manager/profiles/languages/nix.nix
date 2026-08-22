{pkgs, ...}: {
  my.lsp.servers.nixd = {
    package = pkgs.nixd;
  };

  my.languages.nix = {
    extensions = [".nix"];
    lsp = ["nixd"];
    formatter.command = "alejandra";
    helix.auto-format = true;
  };

  home.packages = with pkgs; [
    alejandra
  ];
}
