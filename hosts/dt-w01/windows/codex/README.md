# Windows ChatGPT Desktop → NixOS WSL

桌面端保持 Windows 原生 agent。Stop hook 通过无窗口 `wsl.exe` 调用
NixOS 上的 `codex-notify`，默认收件人为 `xyz`；会话已保存的 `profile`
仍然优先。ServerChan 与企业微信的凭据和服务均留在 WSL。

ServerChan 标题为 `chatgpt-desktop@<hostname>`，此主机显示为
`chatgpt-desktop@dt-w01`。企业微信标题为 `<hostname> ChatGPT Desktop完成`，
此主机显示为 `dt-w01 ChatGPT Desktop完成`。脚本通过 `--title` 传入
企业微信的 `ChatGPT Desktop完成`，WSL 中的 `codex-notify` 自动在前面加上
当前主机名和空格，relay 原样保留此标题。
`-Title` 可覆盖企业微信标题中主机名之后的部分。
`--require-transcript` 跳过没有 transcript 的临时会话，避免桌面端的后台建议生成、
建议安全筛选等内部任务被当作用户任务完成通知；正常会话的 JSON 正文仍原样发送。

Windows 文件直接复制到现有 Codex home，不属于 Home Manager activation。
dt-w01 的 Linux relay 服务通过 `--windows-codex-home /mnt/c/Users/nemo/.codex`
登记此后端；它不是 `my.codex.homes` 中的 Linux home。

先在 NixOS 中运行 `nix flake check`、`check-activation` 与 `hms`，更新通知程序和 relay。
然后从 WSL 复制 hook：

```sh
mkdir -p /mnt/c/Users/nemo/.codex/hooks
cp hosts/dt-w01/windows/codex/notify-wsl.ps1 /mnt/c/Users/nemo/.codex/hooks/codex-notify-wsl.ps1
# 仅在没有 hooks.json 时直接复制；已有文件时合并 Stop 条目，保留其他 hooks。
cp hosts/dt-w01/windows/codex/hooks.json /mnt/c/Users/nemo/.codex/hooks.json
```

本地路径避免 `RemoteSigned` 将 WSL UNC 路径视为远程脚本，无需修改执行策略。
只部署 hook，不安装、卸载或更新 ChatGPT/Codex 应用，也不迁移认证和会话。

复制后需信任这个 hook。可在桌面端的 hook 设置中完成；也可通过原生
App Server 的 `hooks/list` 读取该条目的 `key`、`currentHash`，再用
`config/batchWrite` 将其写入 `hooks.state.<key>.trusted_hash`，并设置
`enabled = true`。仅处理这个脚本，不批量信任其他 hooks。

可先用 `powershell.exe -NonInteractive -File <脚本路径> -InitializeOnly`
生成 `%USERPROFILE%\.codex\wsl-bridge.json`，记录当前原生 home 和可执行文件位置。
脚本参数 `-CodexHome`、`-Distribution`、`-WslUser`、`-NotifyExecutable`、
`-Route` 可覆盖默认值；更换 Windows home 时需同步修改 Linux relay 登记路径。

新建或重新打开桌面会话，使运行时加载 hook；已有会话没有加载时需重新启动桌面端。

## 通知与回复

脚本保留 stdin 中的完整 UTF-8 hook JSON，后台调用 WSL，并始终返回 0。
错误只写入 `%USERPROFILE%\.codex\logs\codex-notify-wsl.log`。
桥接文件在每次 Stop 时刷新，跟随桌面端运行时更新；无需固定版本 hash。
WSL 通过默认 `/mnt/<盘符>/` 访问这些 Windows 路径。

企业微信完成通知中的 `r#...` token 保留 Windows home。引用通知回复时，
WSL relay 调用桥接文件指定的 Windows `codex.exe app-server --listen stdio://`，
只发送 `thread/queue/add`，不在第二个进程中 `thread/resume` 或启动任务。
消息去重与提交状态记录复用现有 relay。Windows 桌面端发现共享持久队列后，
在会话空闲时启动下一轮；空闲状态下外部队列轮询最多约 10 秒。

Windows 回复先收到可继续引用的入队确认，最终结果由 Stop hook 独立通知。
此后端没有桌面端原有 stdio 事件流，因此不提供企业微信中的实时过程流。
请保持桌面端运行并加载该会话；关闭、暂停或未加载的会话需恢复后才能执行队列。
Linux 会话继续使用原有 daemon 和实时流。

取消配置时从 `hooks.json` 删除此脚本对应的 Stop handler，再删除脚本与
`wsl-bridge.json`；不要直接覆盖文件中的其他 handlers 或整个 `hooks.state`。
