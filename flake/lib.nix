{inputs, ...} @ args: {
  flake.lib = inputs.haumea.lib.load {
    src = ../lib;
    inputs = args;
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
