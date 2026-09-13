{lib}: let
  # Shared reasoning levels every gateway model supports. Client renderers
  # project these into their own dialect (codex's catalog, nothing on the
  # opencode side since effort is chosen at runtime).
  reasoning-levels = [
    {
      effort = "low";
      description = "Fast responses with lighter reasoning";
    }
    {
      effort = "high";
      description = "Extra high reasoning depth for complex problems";
    }
    {
      effort = "max";
      description = "Maximum reasoning depth for the hardest problems";
    }
  ];

  # Model facts served by the TCA LiteLLM gateway. `id` is the gateway's bare
  # name, i.e. the Anthropic-protocol route; the OpenAI-protocol route is
  # `<id>-openai` (see openai-slug below). Context windows the gateway does not
  # report via /model/info are filled from the vendors' published specs.
  # Client behaviour, defaults and prompt scaffolding deliberately live in each
  # client's renderer, not here.
  models = [
    {
      id = "deepseek-v4-pro";
      name = "DeepSeek-V4-Pro";
      description = "Frontier reasoning model served by the TCA gateway.";
      context = 1048576;
      output = 384000;
      effort = "max";
      priority = 1;
      vision = false;
    }
    {
      id = "glm-5.3";
      name = "GLM-5.3";
      description = "Zhipu flagship with a 1M-token context window.";
      context = 1048576;
      output = 131072;
      effort = "max";
      priority = 2;
      vision = false;
    }
    {
      id = "kimi-k3";
      name = "Kimi-K3";
      description = "Moonshot K3: 1M context with native vision.";
      context = 1048576;
      output = 128000;
      effort = "max";
      priority = 3;
      vision = true;
    }
    {
      id = "qwen3.8-max";
      name = "Qwen3.8-Max";
      description = "Alibaba flagship, multimodal.";
      context = 1000000;
      output = 131072;
      effort = "max";
      priority = 4;
      vision = true;
    }
    {
      id = "qwen3.7-max";
      name = "Qwen3.7-Max";
      description = "Alibaba Max tier, text only.";
      context = 1000000;
      output = 131072;
      effort = "high";
      priority = 5;
      vision = false;
    }
    {
      id = "doubao-seed-2-0-pro";
      name = "Doubao-Seed-2.0-Pro";
      description = "ByteDance Seed 2.0 Pro, multimodal.";
      context = 256000;
      output = 128000;
      effort = "high";
      priority = 6;
      vision = true;
    }
    {
      id = "glm-5.2";
      name = "GLM-5.2";
      description = "Zhipu GLM-5.2, 1M-token context window.";
      context = 1048576;
      output = 131072;
      effort = "high";
      priority = 7;
      vision = false;
    }
    {
      id = "kimi-k2.7-code";
      name = "Kimi-K2.7-Code";
      description = "Moonshot coding-specialised model.";
      context = 262144;
      output = 128000;
      effort = "high";
      priority = 8;
      vision = false;
    }
    {
      id = "qwen3.7-plus";
      name = "Qwen3.7-Plus";
      description = "Alibaba Plus tier.";
      context = 1000000;
      output = 131072;
      effort = "high";
      priority = 9;
      vision = false;
    }
    {
      id = "qwen3.6-plus";
      name = "Qwen3.6-Plus";
      description = "Alibaba Plus tier, previous generation.";
      context = 1000000;
      output = 131072;
      effort = "high";
      priority = 10;
      vision = false;
    }
    {
      id = "deepseek-flash";
      name = "DeepSeek-Flash";
      description = "Faster DeepSeek tier; upstream route without the V4 suffix.";
      context = 1048576;
      output = 384000;
      effort = "high";
      priority = 11;
      vision = false;
    }
    {
      id = "kimi-k3-extra";
      name = "Kimi-K3 (extra)";
      description = "Kimi K3 through the Moonshot direct channel.";
      context = 1048576;
      output = 128000;
      effort = "high";
      priority = 13;
      vision = true;
    }
    {
      id = "deepseek-v4-flash-local";
      name = "DeepSeek-V4-Flash (local)";
      description = "Self-hosted DeepSeek V4 Flash served through the gateway.";
      context = 1048576;
      output = 384000;
      effort = "high";
      priority = 14;
      vision = false;
    }
    {
      id = "glm-4.6v";
      name = "GLM-4.6V";
      description = "Zhipu vision model, self-hosted.";
      context = 131072;
      output = 8192;
      effort = "low";
      priority = 15;
      vision = true;
    }
  ];

  providers = {
    tca = {
      name = "TCA";
      # LiteLLM gateway. The root serves the Responses API (`/responses`, used
      # by codex); the Anthropic protocol lives under `/v1/messages`, used by
      # opencode and Claude Code. Renderers pick the base URL their SDK
      # expects.
      base-url = "http://10.198.20.38:3821";
      key-env = "TCA_API_KEY";
    };
  };
in {
  inherit reasoning-levels models providers;

  # Gateway naming rule: the OpenAI-protocol route of model `id`.
  openai-slug = id: "${id}-openai";

  # Default gateway model: the highest-priority entry in the ordered list.
  default-model = (lib.lists.head models).id;
}
