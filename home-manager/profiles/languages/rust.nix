{pkgs, ...}: {
  my.lsp.servers.rust-analyzer = {
    package = pkgs.rust-bin.stable.latest.rust-analyzer;
  };

  my.languages.rust = {
    extensions = [".rs"];
    lsp = ["rust-analyzer"];
  };

  home.packages = [
    (pkgs.rust-bin.stable.latest.minimal.override {
      extensions = [
        "clippy"
        "rustfmt"
        "rust-src"
      ];
    })
  ];
}
