{ pkgs, ... }:

{
  programs.bat = {
    enable = true;
    config = {
      italic-text = "always";
    };
    extraPackages = with pkgs.bat-extras; [
      batman
      batdiff
      batwatch
    ];
  };
  home.shellAliases = {
    "cat" = "bat --style header-filename --paging never";
    "man" = "batman";
    "watch" = "batwatch";
  };
}
