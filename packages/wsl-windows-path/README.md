# wsl-windows-path

Read Windows PATH from WSL and print the directories missing from the current
Linux PATH as a colon-prefixed suffix:

```bash
export PATH="$PATH$(wsl-windows-path)"
```

The script converts Windows drive paths to `/mnt/<drive>/...`, preserving their
order and skipping duplicates without regard to Windows path casing or trailing
slashes. It calls Windows PowerShell by absolute path, so it also works in SSH
sessions and systemd services without Windows directories in their PATH.

It prints nothing when Windows PowerShell is unavailable. It requires WSL's
Windows interop and the standard `/mnt/<drive>` mount layout.
