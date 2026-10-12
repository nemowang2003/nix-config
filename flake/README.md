# Flake 输出导航

这里记录仓库定义的 `self.*` 输出入口、用途和使用者。`self` 是当前
flake 的输出集；`self.inputs`、`self.outPath`、`self.sourceInfo` 等由 Nix
提供的输入与来源信息不属于本仓库维护的接口。表格不展开每台主机、每个
package 或配置字段，具体定义以链接中的代码为准。

## 仓库输出

| 输出入口 | 定义位置 | 用途与主要使用者 |
| --- | --- | --- |
| `self.hosts` | [hosts.nix](hosts.nix) | 主机注册表；配置构建、secret 接收者、检查与主机相关 profiles 都从这里取机器元数据。 |
| `self.user-pubkeys` | [hosts.nix](hosts.nix) | 注册表中的 SSH 公钥列表；供系统授权、Home Manager SSH 配置及 `gh-keysync` 使用。 |
| `self.darwinConfigurations.<host>` | [configurations.nix](configurations.nix) | macOS 系统配置，供 `darwin-rebuild` 使用。 |
| `self.nixosConfigurations.<host>` | [configurations.nix](configurations.nix) | NixOS/WSL 系统配置，供 `nixos-rebuild` 使用。 |
| `self.genericConfigurations.<host>` | [configurations.nix](configurations.nix) | generic Linux 的模块求值结果；`generic-rebuild` 使用其中的系统 activation package。 |
| `self.homeConfigurations.<user>@<host>` | [configurations.nix](configurations.nix) | 每台注册主机的独立 Home Manager 配置，供 `home-manager switch` 和 `check-activation` 使用。 |
| `self.packages.<system>` | [packages.nix](packages.nix)、[devshell.nix](devshell.nix) | 导出 [packages/](../packages/) 中的配置关联程序、独立工具 flake inputs 提供的程序，以及 devshell 生成的 `sops-yaml`；模块通过此入口引用 package。 |
| `self.checks.<system>` | [checks.nix](checks.nix) | 自动收集 package 的 `passthru.tests`，检查锁定转写环境的解码、LLM 代理安装导入与注册主机的配置求值；由 `nix flake check` 执行。 |
| `self.devShells.<system>.default` | [devshell.nix](devshell.nix)、[formatter.nix](formatter.nix) | 开发环境、部署和检查命令；启动时设置 sops 密钥环境并生成 `.sops.yaml` 和 `ruff.toml`。 |
| `self.formatter.<system>` | [formatter.nix](formatter.nix) | `nix fmt` 的入口，通过 treefmt 调度 Alejandra 和 Ruff。 |
| `self.formatter-settings` | [formatter.nix](formatter.nix) | 共享格式化规则；其中的 `ruff` 同时供 nixago 和 Home Manager 全局 Ruff 配置使用。 |
| `self.build-nix-settings` | [nix-settings.nix](nix-settings.nix) | 接收主机元数据 `cfg`，返回对应平台的 Nix 设置模块；由 Darwin、NixOS 和 generic profiles 调用。 |
| `self.sops` | [sops.nix](sops.nix) | 加密文件的目录、路径函数及接收者规则；供 secret 模块、相关 profiles 和 nixago 使用，不导出明文 secret。 |
| `self.lib` | [flake.nix](../flake.nix)、[lib/](../lib/) | 自动加载的共享工具与模型元数据，包括模块文件发现、选项镜像、mutable config 合并和 Python 应用构建。 |

`self.apps.<system>`、`self.legacyPackages.<system>`、`self.overlays` 和
`self.nixosModules` 目前没有导出条目，属于 flake-parts 提供的输出容器。
[nixpkgs.nix](nixpkgs.nix) 中应用的 overlays 用于内部 `pkgs` 构建，未通过
`self.overlays` 对外导出。

## 查询示例

```bash
# 注册主机和共享 Ruff 规则
nix eval .#hosts --json
nix eval .#formatter-settings.ruff --json

# 列出当前架构的 packages 和检查，不展开 derivation
nix eval .#packages.aarch64-darwin --apply builtins.attrNames --json
nix eval .#checks.aarch64-darwin --apply builtins.attrNames --json

# 查询指定主机的 Home Manager 配置
nix eval '.#homeConfigurations."nemo@nb-d01".config.home.stateVersion'
```

独立 Python 工具由各自的 `uv.lock` 经 uv2nix 构建；本 flake 统一声明
`pyproject-nix`、`uv2nix` 和 `pyproject-build-systems` inputs，工具 inputs 通过
`follows` 复用这些构建依赖。主机启用及 CUDA 选择仍在 host profiles 中。

系统与 Home Manager 模块通过 special arguments 接收 `self`、`inputs`、
`hostname` 和注册表中的 `cfg`。这些参数的传递路径见
[configurations.nix](configurations.nix)。私有模块选项的导航见
[Home Manager modules](../home-manager/modules/README.md) 和
[Darwin modules](../darwin/modules/README.md)。

## 更新规则

新增、删除、重命名输出入口，或改变其用途、使用方式时，同步更新本文。
主机、package 或子字段的普通增减无需逐项登记；内部实现变化无需更新本文。
