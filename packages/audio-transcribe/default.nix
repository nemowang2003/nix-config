{
  pkgs,
  cudaSupport ? false,
}: let
  lib = pkgs.lib;
  ctranslate2-cpp = pkgs.ctranslate2.override {
    withCUDA = cudaSupport;
    withCuDNN = cudaSupport;
  };
  ctranslate2 = pkgs.python314Packages.ctranslate2.override {inherit ctranslate2-cpp;};
  faster-whisper = pkgs.python314Packages.faster-whisper.override {inherit ctranslate2;};
  cuda-library-path = lib.makeLibraryPath [
    pkgs.cudaPackages.cuda_cudart
    pkgs.cudaPackages.libcublas
    pkgs.cudaPackages.libcurand
    pkgs.cudaPackages.cudnn
  ];
in
  assert !cudaSupport || (pkgs.stdenv.hostPlatform.isLinux && pkgs.stdenv.hostPlatform.isx86_64);
    pkgs.python314Packages.buildPythonApplication {
      pname = "audio-transcribe";
      version = "0.1.0";
      pyproject = true;
      src = ./.;

      build-system = [pkgs.python314Packages.setuptools];
      dependencies = [faster-whisper];
      pythonImportsCheck = ["audio_transcribe"];

      nativeBuildInputs = lib.optionals cudaSupport [pkgs.makeWrapper];
      postFixup = lib.optionalString cudaSupport ''
        # WSL supplies libcuda.so.1 through its Windows driver bridge. cuBLAS,
        # cuDNN, and the other CUDA runtime libraries come from the Nix closure.
        wrapProgram "$out/bin/audio-transcribe" \
          --set AUDIO_TRANSCRIBE_DEFAULT_DEVICE cuda \
          --prefix LD_LIBRARY_PATH : "${cuda-library-path}:/usr/lib/wsl/lib"
      '';
    }
