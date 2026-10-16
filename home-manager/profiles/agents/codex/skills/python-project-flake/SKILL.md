---
name: python-project-flake
description: 为 Python 项目添加或完善 flake.nix，使用 uv2nix 将 uv.lock 中的依赖打包成可构建、运行和被其他 flake 复用的应用或库，并配置开发环境与检查。适用于 Python 项目的 Nix 打包；仅需临时运行 uv 或普通 Python 开发时无需使用。
---

# Python project flake

为独立 Python 仓库提供可复现的 Nix 打包。以 `pyproject.toml` 和
`uv.lock` 为项目与依赖事实来源，使用 uv2nix，不用 Nixpkgs Python
包集合重新解释运行时依赖。保留项目现有构建后端、源码布局和命令名。

## 先确定交付范围

读取项目说明、`pyproject.toml`、`uv.lock`、现有 Nix 文件及调用方。
确认：

- 项目是 CLI、库、服务还是 uv workspace；实际 import 名和
  `[project.scripts]` 的命令名可能与发行名不同。
- `requires-python`、构建后端约束、运行所需 extras、测试依赖组，
  以及 Git/path/workspace 来源。缺少锁文件时用 `uv lock` 生成；已有锁
  用 `uv lock --check` 检查，避免顺手升级无关依赖。
- 目标系统及原生依赖、外部可执行程序、GPU 等限制。解释器既要满足
  项目约束，也要能构建锁定依赖；按实际支持情况选择版本和平台列表。
- 用户需要 Nix 构建产物还是只要开发环境。只需开发环境时，简单的
  `mkShell` 加 Nix 提供的 Python/uv 通常足够，不必引入整套打包。

## 构建与输出

实现前阅读 [uv2nix 配方](references/uv2nix.md)。涉及版本相关 API 时，
检查项目锁定的上游源码或官方文档，使用与锁文件匹配的接口。

- 声明 Nixpkgs、pyproject.nix、uv2nix、build-system-pkgs 输入，
  并用 `follows` 共享它们的 Nixpkgs 和 pyproject.nix 等输入。
  新增必要输入后生成并提交 `flake.lock`；保留已有无关输入版本。
- 加载 workspace，组合构建后端 overlay、uv 锁生成的 overlay、
  项目专用覆盖。默认优先 wheel；根据实际失败补齐构建后端和原生库。
  不把 Nixpkgs Python 包直接塞入 uv2nix 的依赖图来绕过锁定版本。
- 生产环境显式选择项目及必要 extras，避免把 `workspace.deps.all`
  和开发工具带进交付物。库项目无需凭空增加 CLI。
- 提供 `packages.<system>.default` 和有意义的命名输出。CLI 用
  `apps` 明确指向真实入口，特别是发行名与命令名不同或有多个命令时。
  需要整洁应用输出时使用 `mkApplication`；需要 Python 环境供导入时
  可以直接导出 `mkVirtualEnv` 的结果。
- 有外部调用方时提供 `lib.mkPackage = { pkgs, python ? …, … }: …`，
  让调用方复用自己的 Nixpkgs/解释器；按需求暴露 Python set 或 overlay，
  不为每个项目提前设计复杂接口。变更现有输出时检查并兼容调用方。
- 服务模块、主机安装和密钥配置仅在任务需要时添加；具体机器的 GPU
  驱动路径和服务选择留给主机配置或显式启用的参数。

## 开发环境与原生依赖

默认选择 Nix 提供 Python/uv、由 `uv sync` / `uv run` 管理开发环境的
简单 devShell；将 `UV_PYTHON` 指向选定解释器，并按需设置
`UV_PYTHON_DOWNLOADS=never`。不要在 shellHook 中自动联网或修改锁文件。

已有或明确需要 Nix 管理 editable 环境时，采用配方中的 editable
overlay；不要混用 Nix 环境与 uv 创建的第二套环境。用 uv 管理依赖
声明和锁文件，遵守当前用户对 Python 命令的要求。

原生依赖按实际加载方式处理：ELF 链接、`ctypes` / `dlopen`、外部
命令分别验证。优先使用包级补丁、RPATH 或应用 wrapper；只在 Linux
使用相关动态库变量，不将 WSL 路径、CUDA 或 `allowUnfree` 无条件推广
到所有平台。`autoPatchelf` 不保证发现运行时动态加载的库。
追加 hook、构建输入和 passthru 时保留已有值。

## 验证并交付

先将新文件纳入 Git 跟踪，或在临时目录用 `path:` flake 验证，避免
Git flake 忽略未跟踪文件。确认锁文件及 Git/path 依赖源码被纳入构建。

按项目风险执行：

1. 格式化 Nix，运行 `uv lock --check`、`nix flake show` 和
   `nix flake check`。目标平台的输出可求值不代表已在该平台构建成功。
2. 用 `nix build .#<package>` 构建实际交付包；单元测试通过不能替代
   应用构建。对 CLI 执行 `nix run .#<app> -- --help` 或等价的无副作用
   命令；对库从构建环境导入实际模块，避免工作目录源码掩盖缺失文件。
3. 把有价值的验证放入 `checks`：现有测试套件，以及必要的已安装模块
   导入或 CLI smoke check。测试依赖使用锁中声明的测试组；不存在的
   测试依赖先用 `uv add --group …` 正常声明。
4. 运行 `nix develop -c …` 检查所选开发工作流；有 editable 环境时
   验证它指向本地源码。检查不应要求真实凭据、下载模型、调用生产 API
   或启动长期服务。

说明新增输出、使用命令、实际验证的平台和未验证的限制。记录必要的
使用方式到项目现有文档。
