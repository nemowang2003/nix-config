{lib, ...}: {
  programs.eza = {
    enable = true;
    icons = "auto";
  };

  home.shellAliases = {
    ls = lib.mkForce "eza --group-directories-first";
    l = lib.mkForce "eza --long --header --group-directories-first";
    ll = lib.mkForce "eza -long --header --git --group-directories-first";
    la = lib.mkForce "eza --long --header --all --git --group-directories-first";
    lt = "eza --tree";
    tree = "eza --tree";
  };
}
