# Darwin 私有选项导航

这些模块由 [darwin/default.nix](../default.nix) 自动加载。私有选项写在
Darwin 模块配置中；共享配置位于 [profiles/](../profiles/)，主机覆盖位于
[hosts/](../../hosts/) 的 Darwin 目录。

| 选项组 | 定义位置 | 职责与主要使用者 |
| --- | --- | --- |
| `my.nix-homebrew` | [nix-homebrew.nix](nix-homebrew.nix) | 包装 nix-homebrew 的主要用户配置，并增加 `completions.enable`，将 Nix 管理的 Homebrew zsh 补全暴露到系统 profile。共享声明见 [homebrew profile](../profiles/homebrew.nix)。 |

启用 `my.nix-homebrew` 后，镜像配置会传给上游 `nix-homebrew`。上游派生的
package/prefix 等结果不作为这里的输入选项；具体镜像范围、类型和默认值
以模块声明和上游选项为准。

```nix
{cfg, ...}: {
  my.nix-homebrew = {
    enable = true;
    user = cfg.user;
    completions.enable = true;
  };
}
```

`my.nix-homebrew` 管理 Homebrew 本体；安装哪些 formula、cask，以及
activation 行为仍由 nix-darwin 的 `homebrew.*` 配置决定。

## 更新规则

新增、删除、重命名私有选项组，或改变其职责、使用方式时，同步更新本文。
内部实现变化无需更新；精确字段说明维护在模块中的选项声明处。
