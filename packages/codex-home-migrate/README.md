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

## Why this tool exists

The operation here is a complete Codex **storage home rename on the same
machine**. Project working directories stay in place. Credentials, configuration,
plugins, databases and conversation files move together; references to the old
storage location need repair. A directory rename alone does not necessarily
leave sessions resumable.

With Codex 0.162.1, an isolated test created a paginated session, stopped its
app-server and renamed the home. Reading thread metadata still worked, but
resuming by thread ID failed with `no rollout found`. Updating that session's
`threads.rollout_path` to the new location restored resume and access to its
saved turn. This verifies the basic session path repair, not every possible
plugin or custom configuration layout.

Existing community tools solve related operations, but are not a simple,
precise replacement for this one:

- [codex-migrate](https://github.com/ChenglongLi777/codex-migrate) imports and
  merges sessions and repairs project associations. Its `--codex-home` selects
  the target storage directory, while `--map` maps project working directories.
  Its `rebind` can refresh rollout paths, but also updates other thread metadata
  and project registration; it does not relocate and repair the complete home.
  The implementation reviewed was
  [37f5300](https://github.com/ChenglongLi777/codex-migrate/blob/37f5300c15447921baf3b98d8ef09d07a3a60008/src/operations.rs)
  ([SQLite updates](https://github.com/ChenglongLi777/codex-migrate/blob/37f5300c15447921baf3b98d8ef09d07a3a60008/src/sqlite_adapter.rs)).
- [codex-rehome](https://github.com/CalebYcj/codex-rehome) exports and restores
  selected projects, conversations, skills and plugins across Windows/macOS.
  That workflow is broader than renaming a complete local home on NixOS WSL.
  Its supported scenarios and exclusions are documented in its
  [README](https://github.com/CalebYcj/codex-rehome/blob/d32fbf79dc05b1fb4e8eb25b3705eb20d7ece8b0/README.en.md).

Excluding credentials from export is not itself an obstacle: same-machine
credentials can be retained separately. The reason for keeping this small tool
is the narrower operation and explicit source/target selection, without a
session import/merge or guessed project-path mapping. Use the community tools
when their session selection, merge and cross-machine workflows are wanted.

## Why both provider homes have explicit names

Codex 0.162.1 discovers `.codex` as a project-local configuration directory,
skipping it only when it matches the current `CODEX_HOME`. With the official
home at `~/.codex` and the TCA home at `~/.codex-tca`, running TCA in `$HOME`
therefore discovers the official home as project-local configuration. This is
Codex's directory classification rule, not provider-aware home isolation.

If `$HOME` is trusted, allowed settings such as `model` and reasoning effort can
then override TCA's user configuration, and the official `hooks.json` can also
be discovered, subject to hook trust. Provider keys are filtered from project
configuration, so that filtering does not prevent model/hook interference.
See the versioned
[directory check](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/config/src/loader/mod.rs#L1698)
and
[project key filtering](https://github.com/openai/codex/blob/092d3acd6bec3e3a14bdc7e7a2810ab628ab759d/codex-rs/config/src/loader/mod.rs#L89).

This configuration uses `~/.codex-openai` and `~/.codex-tca`. A manual migration
must also ensure that `~/.codex` no longer exposes the old global configuration;
leaving the old directory or a compatibility symlink there preserves the TCA
project-discovery problem. The tool does not choose which home belongs to which
provider: the user determines the source and target on each host.
