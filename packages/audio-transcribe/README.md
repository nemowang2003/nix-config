# audio-transcribe

Transcribe a local audio or video file to UTF-8 text with faster-whisper.

```sh
audio-transcribe meeting.m4a
audio-transcribe meeting.m4a -o meeting.txt --language zh
audio-transcribe interview.mp3 --timestamps --vad
```

The default model is the multilingual `large-v3` CTranslate2 checkpoint. On
dt-w01 the installed package defaults to CUDA with FP16; the generic package
defaults to CPU with int8. The first run downloads the model into
`${XDG_CACHE_HOME:-~/.cache}/faster-whisper/models/`; later runs reuse the
cached copy. `--model` accepts another faster-whisper model name or a local
CTranslate2 model directory. `--model-cache` changes the download location.
The `--device cpu` option uses int8 by default and does not require a GPU.

Only dt-w01 enables CUDA in CTranslate2. Its variant includes CUDA runtime
libraries from nixpkgs. The Windows NVIDIA driver provides
`libcuda.so.1` through WSL at `/usr/lib/wsl/lib`. No separate system FFmpeg is
needed because faster-whisper decodes audio with PyAV.

`--task translate` asks Whisper to translate speech into English. Without it,
the command transcribes in the source language. Language is detected unless
`--language` is provided. Progress and model details go to stderr; transcript
text goes to stdout or the file given with `-o`.
