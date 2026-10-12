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

## dt-w01 provider commands

Start a task that should accept WeCom replies with one of these commands:

```sh
codex-openai          # connects to ~/.codex/app-server-control/openai.sock
codex-tca             # uses the tca profile and connects to ~/.codex/app-server-control/tca.sock
```

The corresponding user services are `codex-openai-app-server.service` and
`codex-tca-app-server.service`. Both listen on their named sockets. The relay
uses `openai.sock` to read thread metadata and routes TCA threads to
`tca.sock`.

Automatic startup of Codex's default app-server daemon is disabled. Plain
`codex` and `codex -p tca` use an embedded server when no default daemon is
already running; `--no-daemon` also bypasses an existing default daemon.
These independent sessions inherit their launch environment. Use
`codex-<provider>` when a task needs WeCom control so the TUI and relay share
the same app-server process and its systemd environment.

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
