declare -A seen=()
IFS=':' read -r -a inherited_path <<< "$PATH"
for directory in "${inherited_path[@]}"; do
  directory="${directory%/}"
  if [[ -n "$directory" ]]; then
    seen["${directory,,}"]=1
  fi
done

# A Windows-launched WSL shell gets this PATH automatically, but SSH and
# systemd do not. Calling the executable by absolute path works from both.
powershell=/mnt/c/WINDOWS/system32/WindowsPowerShell/v1.0/powershell.exe
if windows_path=$("$powershell" -NoProfile -NonInteractive -Command '[Console]::Out.Write($env:Path)' </dev/null 2>/dev/null); then
  windows_path="${windows_path//$'\r'/}"
  IFS=';' read -r -a entries <<< "$windows_path"
  for entry in "${entries[@]}"; do
    entry="${entry#\"}"
    entry="${entry%\"}"
    if [[ "${entry:1:1}" != : || "${entry:2:1}" != '\' ]]; then
      continue
    fi
    drive="${entry:0:1}"
    directory="${entry:3}"
    directory="${directory//\\//}"
    directory="/mnt/${drive,,}/${directory%/}"
    if [[ -z "${seen[${directory,,}]+x}" ]]; then
      seen["${directory,,}"]=1
      printf ':%s' "$directory"
    fi
  done
fi
