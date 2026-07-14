{pkgs, ...}: {
  home.packages = with pkgs; [
    rust-bin.stable.latest.default
    rust-bin.stable.latest.rust-analyzer
  ];
}
