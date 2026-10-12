{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  environment-file = "${config.xdg.configHome}/llama-on-demand/service.env";
  with-key = name: package:
    pkgs.symlinkJoin {
      inherit name;
      paths = [package];
      nativeBuildInputs = [pkgs.makeWrapper];
      postBuild = ''
        wrapProgram "$out/bin/${name}" \
          --run 'set -a; . ${lib.escapeShellArg environment-file}; set +a' \
          --run 'export JA2ZH_SRT_API_KEY="''${JA2ZH_SRT_API_KEY:-$LLAMA_ON_DEMAND_API_KEY}"'
      '';
    };
  llama-package = inputs.llama-on-demand.lib.mkPackage {
    inherit pkgs;
    cudaSupport = true;
  };
  subtitle-package = inputs.ja2zh-srt.lib.mkPackage {
    inherit pkgs;
    cudaSupport = true;
  };
in {
  services.llama-on-demand = {
    enable = true;
    package = with-key "llama-on-demand" llama-package;
    inherit environment-file;
    settings = {
      idle_seconds = 30;
      fit_target_mib = 1024;
      queue_timeout = 3600;
      request_timeout = 3600;
      max_queue = 128;
    };
    models.sakura = {
      path = "${config.xdg.dataHome}/llama-on-demand/models/Sakura-Galtransl-7B-v3.7-IQ4_XS.gguf";
      repo = "SakuraLLM/Sakura-GalTransl-7B-v3.7";
      file = "Sakura-Galtransl-7B-v3.7-IQ4_XS.gguf";
      options = {
        ctx-size = 4096;
        threads = 8;
        threads-batch = 8;
        flash-attn = "on";
        cache-type-k = "q8_0";
        cache-type-v = "q8_0";
      };
    };
  };
  home.packages = [
    (inputs.audio-transcribe.lib.mkPackage {
      inherit pkgs;
      cudaSupport = true;
    })
    (with-key "ja2zh-srt" subtitle-package)
  ];
  home.sessionVariables = {
    JA2ZH_SRT_LLM_URL = "http://127.0.0.1:4000/v1";
    JA2ZH_SRT_LLM_MODEL = "sakura";
  };
  home.activation.local-inference-key = lib.hm.dag.entryAfter ["writeBoundary"] ''
    run ${pkgs.python314}/bin/python - <<'PY'
    import os
    import secrets
    from pathlib import Path
    path = Path(${builtins.toJSON environment-file})
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as output:
            output.write("LLAMA_ON_DEMAND_API_KEY=sk-" + secrets.token_urlsafe(32) + "\n")
    PY
  '';
}
