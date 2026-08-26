{
  lib,
  pkgs,
  ...
}: let
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
in {
  programs.opencode = {
    enable = true;
    enableMcpIntegration = true;

    settings = {
      autoupdate = false;
      share = "disabled";
      permission = "allow";

      provider = {
        deepseek.options.chunkTimeout = 300000;
        tca = {
          npm = "@ai-sdk/anthropic";
          name = "TCA";
          options = {
            baseURL = "http://10.198.20.38:3821/v1";
            chunkTimeout = 300000;
          };
          models = {
            "deepseek-v4-pro" = {
              reasoning = true;
              tool_call = true;
              limit = {
                context = 1048576;
                output = 384000;
              };
            };
            "deepseek-v4-flash" = {
              reasoning = true;
              tool_call = true;
              limit = {
                context = 1048576;
                output = 384000;
              };
            };
            "glm-5.3" = {
              reasoning = true;
              tool_call = true;
              limit = {
                context = 1048576;
                output = 131072;
              };
            };
            "glm-5.2" = {
              reasoning = true;
              tool_call = true;
              limit = {
                context = 1048576;
                output = 131072;
              };
            };
            "glm-5.2-w4a8" = {
              reasoning = true;
              tool_call = true;
              limit = {
                context = 1048576;
                output = 131072;
              };
            };
            "qwen3.7-max" = {
              reasoning = true;
              tool_call = true;
              limit = {
                context = 1000000;
                input = 983616;
                output = 131072;
              };
            };
            "qwen3.8-max" = {
              reasoning = true;
              tool_call = true;
              attachment = true;
              modalities.input = [
                "text"
                "image"
                "video"
              ];
              limit = {
                context = 1000000;
                input = 991808;
                output = 131072;
              };
            };
            "kimi-k2.5" = {
              reasoning = true;
              tool_call = true;
              attachment = true;
              modalities.input = [
                "text"
                "image"
                "video"
              ];
              limit = {
                context = 262144;
                output = 128000;
              };
            };
            "kimi-k2.6" = {
              reasoning = true;
              tool_call = true;
              attachment = true;
              modalities.input = [
                "text"
                "image"
                "video"
              ];
              limit = {
                context = 262144;
                output = 128000;
              };
            };
            "doubao-seed-2-0-pro" = {
              reasoning = true;
              tool_call = true;
              attachment = true;
              modalities.input = [
                "text"
                "image"
                "video"
              ];
              limit = {
                context = 256000;
                output = 128000;
              };
            };
          };
        };
      };

      lsp = true;
    };

    package = opencode;
  };
}
