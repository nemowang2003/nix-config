{
  pkgs,
  pyproject-nix,
  python-application,
  cudaSupport ? false,
}: let
  lib = pkgs.lib;
  ctranslate2-cpp = pkgs.ctranslate2.override {
    withCUDA = cudaSupport;
    withCuDNN = cudaSupport;
  };
  ctranslate2 = pkgs.python314Packages.ctranslate2.override {inherit ctranslate2-cpp;};
  faster-whisper = pkgs.python314Packages.faster-whisper.override {inherit ctranslate2;};
  application = python-application {
    inherit pkgs pyproject-nix;
    root = ./.;
    python-packages = pkgs.python314Packages // {inherit faster-whisper;};
    # Unit tests provide a fake WhisperModel; no model/runtime closure needed.
    test-dependencies = [];
  };
  cuda-library-path = lib.makeLibraryPath [
    pkgs.cudaPackages.cuda_cudart
    pkgs.cudaPackages.libcublas
    pkgs.cudaPackages.libcurand
    pkgs.cudaPackages.cudnn
  ];
in
  assert !cudaSupport || (pkgs.stdenv.hostPlatform.isLinux && pkgs.stdenv.hostPlatform.isx86_64);
    application.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or []) ++ lib.optionals cudaSupport [pkgs.makeWrapper];
      postFixup =
        (old.postFixup or "")
        + lib.optionalString cudaSupport ''
          # WSL supplies libcuda.so.1 through its Windows driver bridge. cuBLAS,
          # cuDNN, and the other CUDA runtime libraries come from the Nix closure.
          wrapProgram "$out/bin/audio-transcribe" \
            --set AUDIO_TRANSCRIBE_DEFAULT_DEVICE cuda \
            --prefix LD_LIBRARY_PATH : "${cuda-library-path}:/usr/lib/wsl/lib"
        '';
    })
