# codex-home-migrate

Explicitly move an inactive Codex home and repair its stored absolute paths.
The user supplies both directories; the tool has no default source or target.
It is available as a flake package for `nix run`, and is not installed by Home
Manager, added to the devshell, or invoked by activation.

The default and `--check` modes only validate. Moving and updating files
requires `--apply`:

```sh
nix run .#codex-home-migrate -- --help
nix run .#codex-home-migrate -- --check /absolute/source /absolute/target
nix run .#codex-home-migrate -- --apply /absolute/source /absolute/target
```

Choose paths based on the actual homes on that machine. If transferring an
existing home into a newly configured location, migrate before Home Manager
creates that destination; the tool refuses to merge existing directories.
Close sessions and stop the source home's daemon using the original Codex
binary before applying. The tool refuses a source with a listening app-server
socket, symlinked homes, or two existing directories.

Migration renames the directory, preserving credentials and conversation
history. It backs up SQLite databases and changed operational metadata under
`<target>/home-migration-backup`, updates stored path columns, daemon recovery
records, plugin metadata, TOML paths and shell snapshots. Conversation JSONL
and historical messages are unchanged. Interrupted migrations can be retried
with the same explicitly supplied paths. `--check` is a precondition check,
not a full compatibility audit or a preview of every metadata change.

This tool uses internal Codex storage formats and is currently maintained here
as a manually invoked utility. It is independent of the host configuration and
can be extracted into a separate flake project later.
