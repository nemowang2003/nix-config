{pkgs, ...}: {
  my.lsp.servers.nixd = {
    package = pkgs.nixd;
  };

  my.languages.nix = {
    extensions = [".nix"];
    lsp = ["nixd"];
    formatter.command = "alejandra";
    helix.autoFormat = true;
  };

  home.packages = with pkgs; [
    alejandra
  ];
}
