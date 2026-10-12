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
| `my.codex` | [codex.nix](codex.nix) | 包装上游 `programs.codex`，生成独立的官方与 TCA home，组合 instructions，并在 activation 时合并可写配置；由 [Codex profile](../profiles/agents/codex/default.nix) 和主机覆盖使用。 |
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

每台主机同时生成 `~/.codex-openai` 和独立的 `~/.codex-tca`。官方 `codex`
启动器固定使用 `.codex-openai`，保留同一包的补全与辅助程序。
activation 只维护声明的配置，不检查、猜测或迁移旧 home，也不搬动旧 profile。
已有 home 的迁移由用户先手动运行
[`codex-home-migrate`](../../packages/codex-home-migrate/README.md)，明确指定源与目标。
该工具只通过 `nix run .#codex-home-migrate` 使用，不安装进 Home Manager 或 devshell PATH。
`codex-tca`
设置 `CODEX_HOME` 后调用同一 Codex 二进制，并复用 `codex` 的 zsh 补全；
不传 `--profile` 或 `--remote`，由 Codex 自动启动各自的 daemon。session、
认证与模型偏好均不共享；instructions、用户技能、rules 和 MCP 声明用于两边。
TCA 配置由上游渲染的声明配置与 `tca-settings` 合并，去掉
`tca-removed-paths` 指定的官方专属字段；`tca-hooks` 可单独声明 TCA hooks。
共享 [Codex profile](../profiles/agents/codex/default.nix) 为两边 Stop hooks
传递不同的 `--codex-home`，通知与企业微信回复 token 因此能直接识别所属 daemon。
OpenAI plugins/apps 配置仅用于官方 home。

主 TOML 与 profile TOML 在 activation 时逐字段合并，保留声明中未提及的
运行时数据；删除声明不会自动清除已有字段。`removed-paths`、
`tca-removed-paths`、`profile-removed-paths` 分别清理官方配置、TCA 配置和
普通 profile 的旧路径。旧 TCA profile 的模型偏好和历史如何迁移，也由用户手动决定。

`CODEX_NOTIFY_HOMES` 登记两个 home，供通知维护命令、session 列表和补全
查询两个独立数据库。dt-w01 的 relay 使用通知里的 home；旧 token 回退到
数据库查找。回复时只启动或复用所属 home 的 daemon，无需 app-server systemd 服务。

```nix
{
  my.codex = {
    enable = true;
    contexts = ["Use the project's development environment."];
    settings.tui.status_line = ["current-dir"];
    tca-settings.model_provider = "tca";
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
