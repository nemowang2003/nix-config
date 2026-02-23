{ pkgs, ...}:

{
  home = {
    packages = [
      pkgs.tree
    ];
    shellAliases = {
      tree = "tree --gitignore";
    };
  };
}
