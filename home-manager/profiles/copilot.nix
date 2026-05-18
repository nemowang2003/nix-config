{...}: {
  programs.helix.languages = {
    language-server.copilot = {
      command = "helix-assist";
      # TODO: sops
    };

    languages = [
      {
        name = "git-commit";
        language-servers = ["copilot"];
      }
    ];
  };
  # TODO: copilot install & config
}
