{
  inputs,
  lib,
  ...
}: {
  flake.lib = inputs.haumea.lib.load {
    src = ../lib;
    inputs = {inherit lib;};
    transformer = [
      (
        cursor: dir:
          if dir ? default
          then dir.default
          else dir
      )
    ];
  };
}
