{pkgs, ...}: {
  my.lsp.servers.rust-analyzer = {
    package = pkgs.rust-bin.stable.latest.rust-analyzer;
    extensions = [".rs"];
    language = "rust";
  };

  home.packages = with pkgs; [
    rust-bin.stable.latest.default
  ];
}
