{ lib, pkgs, ... }:

{
  # helix
  programs.helix = {
    enable = true;
    defaultEditor = true;

    settings = {
      editor = {
        line-number = "relative";
        cursorline = true;
      };
    };

    extraPackages = with pkgs; [
      tombi
      vscode-langservers-extracted
    ];
  };
}
