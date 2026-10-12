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
| `my.codex` | [codex.nix](codex.nix) | 包装上游 `programs.codex`，组合 instructions，并在 activation 时合并可写的主配置和 profile 文件；由 [Codex profile](../profiles/agents/codex/default.nix) 和主机覆盖使用。 |
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

`my.codex` 镜像上游的主要配置选项，另提供 `contexts` 和
`profile-removed-paths`。`contexts` 接受文本或文件路径，组合后交给上游
生成 instructions。主 TOML 与 profile TOML 在 activation 时逐字段合并，
保留声明中未提及的运行时数据；删除声明不会自动清除已有字段。
`profile-removed-paths` 可显式删除指定 profile 的旧 TOML 路径。
`custom-instructions` 是重命名为 `context` 的兼容入口。

```nix
{
  my.codex = {
    enable = true;
    contexts = ["Use the project's development environment."];
    settings.tui.status_line = ["current-dir"];
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
