{...}: {
  programs.tmux = {
    enable = true;
    baseIndex = 1;
    terminal = "screen-256color";
    mouse = true;
    focusEvents = true;
  };
}
