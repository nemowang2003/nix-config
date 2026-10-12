# codex-wecom-relay

The relay delivers `codex-notify` messages to WeCom and routes replies back
to the quoted Codex thread. A reply uses the experimental app-server
`thread/queue/add` request. The app-server persists queued messages and starts
each one as a separate turn when the thread becomes idle. The relay matches
the resulting user message by `clientUserMessageId` before streaming that
turn's agent output to WeCom.

Both WebSocket connections use asyncio. Replies are submitted in callback
order; once a reply is queued, its response can stream alongside later replies.
Cancelling a callback closes its app-server connection.

## Independent Codex homes

Every host provides two commands, with the same Codex binary and completion:

```sh
codex                # ~/.codex-openai, official OpenAI configuration
codex-tca            # ~/.codex-tca, TCA gateway and model catalog
```

Codex automatically starts or reuses a daemon for each home. The two homes
keep independent configuration, authentication, model defaults and sessions.
`codex-tca` sets `CODEX_HOME`; it does not pass `--profile` or `--remote`.
No app-server systemd services are installed.

Each home's Stop hook passes its own `--codex-home` to `codex-notify`. The
outbox entry and persisted reply token retain that home. The relay validates
it against the homes supplied with repeated `--codex-home` arguments, then
runs `CODEX_HOME=<owning-home> <codex-bin> app-server daemon start` before
connecting to the returned Unix socket. A missing daemon for the other home
has no effect. Existing tokens without a home use read-only database lookup;
missing or ambiguous thread ownership is reported instead of guessed.

Only the relay remains a dt-w01 systemd user service. Its environment includes
the shared sops environment and Windows PATH so daemons first started by a
WeCom reply can use the TCA credentials and WSL tools. A running daemon keeps
its existing environment.

Home Manager activation only maintains declared configuration. Home and
profile migrations are manual operations; users choose the source and target
explicitly. The optional [migration tool](../codex-home-migrate/README.md) is
available through `nix run`, without installation into the user profile.

## Queue limitation

Codex TUI keeps Tab-queued follow-ups in its own local queue. They do not
appear in the app-server's `thread/queue/list`. If a TUI follow-up and a WeCom
reply are pending when the thread becomes idle, either client may start the
next turn first. If the app-server queue starts the WeCom turn first, the TUI's
later `turn/start` may steer its follow-up into that turn. Multiple WeCom
replies use the same app-server queue and start as separate turns in accepted
queue order.

Changing this cross-client ordering requires a shared queue in Codex TUI and
app-server, or an idle-only turn submission API for the TUI. This relay cannot
inspect the TUI's local Tab queue.
