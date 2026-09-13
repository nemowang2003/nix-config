{
  self,
  lib,
  pkgs,
  ...
}: let
  models-lib = self.lib.models;
  pkg = pkgs.llm-agents.opencode;
  # Keep opencode-only runtime flags out of the global session environment.
  opencode = pkgs.writeShellApplication {
    name = "opencode";
    text = ''
      export OPENCODE_DISABLE_LSP_DOWNLOAD=true
      export OPENCODE_EXPERIMENTAL_LSP_TOOL=true
      export OPENCODE_EXPERIMENTAL_LSP_TY=true

      exec ${lib.getExe pkg} "$@"
    '';
  };

  # Registry -> opencode model entry. Only the facts opencode actually reads:
  # limit drives token budgeting and compaction (context + output are a
  # required pair), reasoning/tool_call mark capabilities, and vision models
  # additionally get attachment and input modalities. The anthropic npm
  # handles thinking blocks natively, so no interleaved field is needed.
  render-model = model:
    {
      name = model.name;
      reasoning = true;
      tool_call = true;
      limit = {
        context = model.context;
        output = model.output;
      };
    }
    // lib.optionalAttrs model.vision {
      attachment = true;
      modalities.input = [
        "text"
        "image"
        "video"
      ];
    };
in {
  programs.opencode = {
    enable = true;
    enableMcpIntegration = true;

    settings = {
      autoupdate = false;
      share = "disabled";
      permission = "allow";

      provider = {
        # Built-in models.dev provider; only the long-reasoning chunk timeout
        # is overridden.
        deepseek.options.chunkTimeout = 300000;
        tca = {
          npm = "@ai-sdk/anthropic";
          name = models-lib.providers.tca.name;
          options = {
            baseURL = "${models-lib.providers.tca.base-url}/v1";
            chunkTimeout = 300000;
          };
          models = lib.listToAttrs (
            map
            (model: lib.nameValuePair model.id (render-model model))
            models-lib.models
          );
        };
      };

      lsp = true;
    };

    package = opencode;
  };
}
