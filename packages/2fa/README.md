# 2fa

`2fa github` prints the current six-digit TOTP code and copies it to the
clipboard. `2fa --list` lists sites; `2fa --no-copy github` only prints the code.
Zsh completion lists the available sites.

Keys are read from `${XDG_CONFIG_HOME:-$HOME/.config}/2fa/keys/<site>`.
The generator uses SHA-1 and a 30-second period, with Python's standard library.
Its HOTP implementation is adapted from [MinTOTP](https://github.com/susam/mintotp)
under the included MIT license.

Clipboard support uses macOS `pbcopy`, WSL `clip.exe`, Wayland `wl-copy`,
X11 `xclip`/`xsel`, or tmux, when available. If copying fails, the code remains
available on stdout and a warning is printed on stderr.

Home Manager installs this package only on trusted hosts. All files in the
encrypted `secrets/trusted/2fa.json` tree are materialized under `~/.config/2fa/`
at their original relative paths, with mode 0600. This includes recovery codes
without a matching TOTP key. Edit that file with `sops` to update the shared
contents; new JSON leaves automatically become secret files at activation.
The encrypted file is a snapshot, not a live sync of local edits.
