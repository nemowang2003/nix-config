{
  inputs,
  lib,
  ...
}: {
  flake.lib = inputs.haumea.lib.load {
    src = ../lib;
    inputs = {inherit lib;};
  };
}
