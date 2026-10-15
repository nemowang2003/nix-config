# Home Manager 私有选项导航

这里的 `my.*` 是 Home Manager 模块选项，使用时写入模块的配置，而非
`self` 下的 flake 输出。模块由 [home-manager/default.nix](../default.nix)
自动加载；共享使用方式通常写在 [profiles/](../profiles/) 中，主机选择
与覆盖写在 [hosts/](../../hosts/) 中。

本文记录选项组的职责和入口。完整字段、类型、默认值及具体约束以对应
模块的 `mkOption.description` 和配置代码为准。

| 选项组 | 定义位置 | 职责与主要使用者 |
| --- | --- | --- |
| `my.lsp.servers` | [lsp.nix](lsp.nix) | 按 ID 登记 LSP 的 package/command、参数及是否向 PATH 和 agent 暴露；由 `my.languages` 和 agent profiles 消费。启用的条目必须提供 package 或 command。 |
| `my.languages` | [languages.nix](languages.nix) | 按语言登记扩展名、项目根标志、LSP 引用和 formatter；生成 Helix 的语言配置，并供 agent profiles 选择 LSP。引用的 LSP 必须存在且启用。 |
| `my.codex` | [codex.nix](codex.nix) | 包装上游 `programs.codex`，生成独立的官方与可扩展的额外 home，组合 instructions，并在 activation 时合并可写配置；由 [Codex profile](../profiles/agents/codex/default.nix) 和主机覆盖使用。 |
| `my.secrets` | [secrets.nix](secrets.nix) | `files` 登记整文件或 keyed secret 的来源和落地路径；`twofa` 保留账号形状的 2FA 文件登记。模块还自动 materialize 可用的分组 env 文件，供 zsh 导出环境变量。 |
| `my.skland` | [skland.nix](skland.nix) | Skland 自动签到的选项骨架。目前启用仅产生警告，尚未实现 service、timer、secret 渲染或 credential 合并，不能据此部署签到任务。 |

## 声明与引用 LSP

```nix
{pkgs, ...}: {
  my.lsp.servers.nixd.package = pkgs.nixd;
  my.languages.nix = {
    extensions = [".nix"];
    lsp = ["nixd"];
    formatter.command = "alejandra";
    helix.auto-format = true;
  };
}
```

可在语言或 LSP 条目的 `agent.enable` 中关闭 agent 消费；语言条目的
`helix.enable` 控制编辑器消费。现有语言声明见
[profiles/languages/](../profiles/languages/)。

## Codex 的可写配置

`my.codex` 镜像上游的主要配置选项。`contexts` 接受文本或文件路径，
组合后交给上游生成 instructions；`custom-instructions` 是 `context` 的兼容入口。

每台主机生成 `~/.codex-openai`、`~/.codex-tca` 和 `~/.codex-wcy`。
官方 `codex` 启动器固定设置 `CODEX_HOME=~/.codex-openai`，保留同一包的补全与辅助程序。
`my.codex.settings` 等顶层声明默认写入官方 home，并作为额外 home 的公共声明来源。
activation 只维护声明的配置，不检查、猜测或迁移旧 home，也不搬动旧 profile。
已有 home 的迁移由用户先手动运行
[`codex-home-migrate`](../../packages/codex-home-migrate/README.md)，明确指定源与目标。
该工具只通过 `nix run .#codex-home-migrate` 使用，不安装进 Home Manager 或 devshell PATH。

新增 home 只需声明 `my.codex.homes.<名称> = {};`，即生成 `codex-<名称>` 命令，
固定设置 `CODEX_HOME=~/.codex-<名称>` 后调用原始 Codex 二进制，并复用 `codex` 的 zsh 补全。
名称使用小写字母、数字和连字符；`openai` 保留给官方 home。
`reserved-home-names` 还保留 `list-sessions`、`generate-profile`、`notify`、
`wecom-relay`、`home-migrate` 等辅助命令后缀；新增辅助命令时扩展此列表，避免覆盖启动器。
每个额外 home 继承声明的 instructions、skills、rules、MCP、配置与普通 profiles。
认证、session、运行时模型选择和自行安装的 plugins/skills 各自独立，不复制其他 home 的运行时文件。
WCY 仅声明空 home，使用公共配置与默认 OpenAI provider；TCA 在 `homes.tca.settings`
中覆盖 provider 和 model catalog，不影响其他 home。

`forall-codex` 按官方 home、额外 home 名称排序的顺序调用各启动器，原样传递参数，
并复用 Codex 的 zsh 补全。每个命令执行一次，某个失败后仍执行其余命令；
全部成功返回 0，否则返回 1；不带参数显示用法并返回 2。例如：

```sh
forall-codex app-server daemon stop
forall-codex app-server daemon update --from-cli --yes
```

更新命令会替换各 home 的 daemon 包并可能打断正在执行的任务；activation 不自动运行这些命令。

`homes.<名称>.settings` 与公共声明合并；`homes.<名称>.removed-paths` 在合并后移除指定字段，
默认继承顶层 `removed-paths`。TCA 单独声明自己的移除列表。
`hooks-for-home` 接受额外 home 的绝对路径并生成 hooks，默认返回顶层 `hooks`；
也可以用 `homes.<名称>.hooks` 单独覆盖。共享 [Codex profile](../profiles/agents/codex/default.nix)
为各 home 的 Stop hooks 传递各自的 `--codex-home`，通知和企业微信回复可据此定位 daemon。
旧 `tca-settings`、`tca-hooks`、`tca-removed-paths` 选项保留为对应 `homes.tca.*` 的兼容入口。

所有 home 都使用显式名称，是为了避免在 `$HOME` 运行 TCA 时，把另一份
`~/.codex` 全局配置识别为 project-local 配置。Codex 0.162.1 只跳过与当前
`CODEX_HOME` 相同的 `.codex`；受信任的项目层仍可覆盖模型设置并发现 hooks。
因此迁移后应让旧 `~/.codex` 不再承载全局配置，也不保留兼容 symlink。
详细原因、版本化源码与迁移工具的适用范围见
[迁移工具 README](../../packages/codex-home-migrate/README.md)。

主 TOML 与 profile TOML 在 activation 时逐字段合并，保留声明中未提及的
运行时数据；删除声明不会自动清除已有字段。`removed-paths`、
`homes.<名称>.removed-paths`、`profile-removed-paths` 分别清理官方配置、额外 home 配置和
普通 profile 的旧路径。旧 TCA profile 的模型偏好和历史如何迁移，也由用户手动决定。

只读 `home-directories` 列出所有 home 的绝对路径。`CODEX_NOTIFY_HOMES`、session 列表、
通知补全与 dt-w01 relay 自动使用该列表，无需在新增 home 时逐个修改。
dt-w01 的 relay 使用通知里的 home；旧 token 回退到数据库查找。回复时只启动或复用所属 home 的 daemon，无需 app-server systemd 服务。

```nix
{
  my.codex = {
    enable = true;
    contexts = ["Use the project's development environment."];
    settings.tui.status_line = ["current-dir"];
    homes.wcy = {}; # codex-wcy 使用 ~/.codex-wcy
    homes.tca.settings.model_provider = "tca";
  };
}
```

## Secret 文件登记

```nix
{config, lib, cfg, ...}: {
  my.secrets.files.example = lib.mkIf cfg.trusted {
    scope = "trusted";
    file = "example.json";
    format = "json";
    key = "account/token";
    path = "${config.xdg.configHome}/example/token";
  };
}
```

`scope` 选择加密文件所在的 common、trusted 或当前 host 目录；访问范围
由 sops 接收者控制。登记 trusted 文件的 profile 应按 `cfg.trusted` 门控。
没有指定落地路径的条目仍可通过 sops placeholder 使用。

当前 [2FA profile](../profiles/2fa.nix) 使用 `my.secrets.files`，将加密 JSON
树的文件内容按原相对路径分发到 `~/.config/2fa/`，并只在 trusted 主机启用。
它没有使用 `my.secrets.twofa`；后者要求不同的账号 JSON 结构，不能直接用于
当前的目录快照。env 的分组文件由模块自动处理，不需要逐变量登记。

## 更新规则

新增、删除、重命名私有选项组，或改变其职责、使用方式时，同步更新本文。
内部实现变化无需更新；精确字段说明维护在模块中的选项声明处。
