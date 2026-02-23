{ pkgs, ... }:

{
  programs.ruff = {
    enable = true;
    settings = {
      line-length = 100;
      lint = {
        select = [
          "E" # pycodestyle errors
          "W" # pycodestyle warnings
          "F" # pyflakes
          "I" # isort
        ];
        ignore = [ "E501" ];
      };
    };
  };
}
