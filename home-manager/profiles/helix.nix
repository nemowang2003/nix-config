{pkgs, ...}: {
  programs.helix = {
    enable = true;
    defaultEditor = true;

    settings = {
      editor = {
        cursorline = true;
        line-number = "relative";
        true-color = true;
      };
    };

    extraPackages = with pkgs; [
      tombi
      vscode-langservers-extracted
    ];
  };
}
