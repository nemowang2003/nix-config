# codex-wecom-relay

The relay delivers `codex-notify` messages to WeCom and routes replies back
to the quoted Codex thread. A reply uses the experimental app-server
`thread/queue/add` request. The app-server persists queued messages and starts
each one as a separate turn when the thread becomes idle. The relay matches
the resulting user message by `clientUserMessageId` before streaming that
turn's agent output to WeCom.

The stream contains assistant text from the turn's intermediate and final
messages; the Stop-hook notification contains only `last_assistant_message`.
The notification outbox can carry an exact `title`, supplied by
`codex-notify notify --title` after prefixing the local hostname;
the relay preserves it in every part.
Entries without a title keep the legacy `Codex 完成` heading.
Once that notification is fully acknowledged, the still-editable stream drops
the final assistant message to avoid repeating the answer. Both carry a stable reply token identifying the
owning home and thread, including the stream's initial queued acknowledgement.
An unrecognized quote is rejected; only an unquoted message can fall back to
the sender's latest completion notification. The stream does not
include command stdout or reasoning events.

Both WebSocket connections use asyncio. Submission locks preserve callback
order within each home/thread; other homes and threads proceed independently.
Each app-server RPC has a 30-second deadline (daemon startup has a separate
60-second deadline). Once a reply is queued, its response can stream alongside
later replies. Cancelling a callback closes its app-server connection.

Every two seconds, the relay checks the accumulated text and sends a stream
snapshot only if it has changed. This check continues even when no further
delta arrives. Completing an assistant message flushes immediately.
Each incoming WeCom request has its own buffer and stream IDs, and app-server
events are filtered to the submitted turn. Concurrent requests do not share
stream content. Within a single turn, assistant messages are separated by a
blank line (`\n\n`), without adding separators between deltas of the same message.
Existing newlines at message boundaries are normalized to one blank line.

## Length limits and completion deduplication

Every stream snapshot and completion notification fits the [20,480 UTF-8 byte
limit](https://github.com/WecomTeam/aibot-node-sdk/blob/main/src/types/api.ts),
counting all visible text, separators, headings and reply-token footers. JSON
escaping is not counted as content. There is no soft threshold or rolling-tail
truncation. On overflow, the relay seals the largest prefix ending at a complete
assistant-message boundary that fits, and continues in a new stream ID under
the original callback `req_id`. It can shrink the old snapshot before sealing
it so the next assistant message moves intact into the new bubble.

If one assistant message alone exceeds the budget, its text is hard-split at
Unicode code-point boundaries. No files are uploaded; newline or Markdown
syntax boundaries are not required, so a code block or table may span bubbles.
Completion notifications use the same byte accounting and hard splitting.
Every part carries a reply token; already acknowledged notification parts are
checkpointed so retries resume at the remaining text. All stream updates also
wait for an acknowledgement before another update for that callback is sent.

The Stop hook includes `turn_id` in its outbox entry. Delivery receipts in
`delivered.json` are keyed by home, thread, turn and recipient, and recorded only
after **every** notification part is acknowledged. At turn completion the stream
waits up to 30 seconds for this receipt before removing its last assistant
message. Missing, rejected or legacy notifications without a turn ID leave the
stream answer intact. If nothing remains after removal, the bubble finishes
with a short replyable completion hint. Already finished bubbles cannot be
revised: if the final assistant message was itself hard-split, its previously
sealed fragments remain visible and only its editable suffix can be removed.

## Submission recovery

`submissions.json` in the relay state directory persists WeCom `msgid` submission
states using atomic replacement and fsync, without storing the message text:

| State | Retry policy |
| --- | --- |
| `preparing` | No queue request has been sent. After restart, becomes `failed`. |
| `submitting` | Persisted before sending `thread/queue/add`. After interruption or restart, becomes `unknown`. |
| `failed` | Setup failed or the server explicitly rejected the queue request. The same `msgid` can retry. |
| `accepted` | Queue confirmation and submission ID received. Repeated callbacks never enqueue it again. |
| `unknown` | The queue request may have reached Codex, but confirmation was lost. Repeated callbacks never enqueue it again. Check the Codex thread manually before deciding whether to send a new message. |

After acceptance, a lost progress connection is reported as “已入队，进度连接断开”,
not a failed injection. The Stop hook still supplies the independent completion
notification. Accepted/unknown records are retained across relay restarts and
are not automatically expired. A corrupt ledger stops relay startup instead of
silently forgetting duplicate protection. Keep this file when moving relay state.

## Independent Codex homes

Every host provides three commands, with the same Codex binary and completion:

```sh
codex                # ~/.codex-openai, official OpenAI configuration
codex-tca            # ~/.codex-tca, TCA gateway and model catalog
codex-wcy            # ~/.codex-wcy, shared configuration and default provider
```

Codex automatically starts or reuses a daemon for each home. The homes
keep independent configuration, authentication, model defaults and sessions.
Additional homes declared in `my.codex.homes` are automatically registered with
notification maintenance and the dt-w01 relay.

`codex-tca` and `codex-wcy` set `CODEX_HOME`; neither passes `--profile` or `--remote`.
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

The relay and notification hook use absolute Nix store paths. The relay is not
installed into the Home Manager PATH; `codex-notify` remains available there for
manual routing with `pick`, `route <thread-id> <name>`, and `cleanup`.

## Native Windows desktop through WSL

On dt-w01, `--windows-codex-home /mnt/c/Users/nemo/.codex` registers the native
desktop home separately from Linux homes. The Windows Stop hook is copied
manually, outside Home Manager activation; see the
[hook configuration guide](../../hosts/dt-w01/windows/codex/README.md).

Each Stop refreshes `wsl-bridge.json` in the native home with the owning
Windows runtime executable and native home path. The relay invokes that binary
through WSL interop, passing native `CODEX_HOME` with `WSLENV=...:CODEX_HOME/w`.
It submits `thread/queue/add` over stdio without resuming the thread in the
second process. The desktop's queue watcher executes the reply when its loaded
thread becomes idle. Windows drive paths use WSL's default `/mnt/<drive>` mounts.

This backend sends a finished, replyable queue acknowledgement; final output
arrives through the Stop hook. It does not subscribe to the desktop process's
stdio events, so Windows replies have no intermediate live stream. Keep the
desktop running with that thread loaded; paused or unloaded threads need to be
resumed. Submission certainty and duplicate protection use the same ledger as
Linux replies. Native homes are never inspected with Linux SQLite connections.
