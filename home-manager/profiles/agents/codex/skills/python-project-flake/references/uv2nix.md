# uv2nix 配方与取舍

以下是可按项目组合的结构，项目名、解释器、extras 和系统列表均需
从目标仓库确定，不是可原样复制的完整 flake。

## 输入与 Python set

用 `follows` 让各构建工具共享依赖输入：

```nix
inputs = {
  nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  pyproject-nix = {
    url = "github:pyproject-nix/pyproject.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  uv2nix = {
    url = "github:pyproject-nix/uv2nix";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.pyproject-nix.follows = "pyproject-nix";
  };
  pyproject-build-systems = {
    url = "github:pyproject-nix/build-system-pkgs";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.pyproject-nix.follows = "pyproject-nix";
    inputs.uv2nix.follows = "uv2nix";
  };
};
```

在 outputs 的共享作用域加载 workspace：

```nix
workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = self; };
overlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };
mk-python-set = { pkgs, python }:
  (pkgs.callPackage pyproject-nix.build.packages { inherit python; }).overrideScope (
    pkgs.lib.composeManyExtensions [
      pyproject-build-systems.overlays.wheel
      overlay
      # 需要时追加项目专用 overlay；从 prev 取被覆盖的包，避免递归。
    ]
  );
```

`uv.lock` 不锁构建后端，build-system-pkgs 提供常用后端。构建仍报缺失
后端或版本不兼容时，检查锁定的 build-system-pkgs 和项目
`[build-system].requires`，按上游接口补覆盖，保留 Python 项目的后端
选择。不要为了 Nix 随意改写后端版本约束。

## 交付环境

假设项目发行名为 `example`，CLI extra 名为 `cli`：

```nix
python-set = mk-python-set { inherit pkgs python; };
environment = python-set.mkVirtualEnv "example-env" { example = ["cli"]; };
application = (pkgs.callPackages pyproject-nix.build.util {}).mkApplication {
  venv = environment;
  package = python-set.example;
};
```

无 extra 时用 `[]`。`workspace.deps.default` 适合默认 workspace 成员
集合；`workspace.deps.all` 适合开发环境。对多成员 workspace 仔细检查
成员、extras 和 dependency groups 的选择，避免将其全部作为生产依赖。
需要测试组时检查锁定 uv2nix 的 `workspace.deps.groups` 接口，并将
所需组与项目选择合并。

`mkApplication` 只暴露应用文件，完整 Python 环境可以通过独立输出或
passthru 提供给导入检查和调用方。测试 CLI 时从非源码目录运行，确认
使用的是包内源码。若使用 `${self}/tests` 运行测试，区分源代码测试和
已安装包测试；不要给后者设置指向源码的 `PYTHONPATH`。

## 两种开发工作流

简单 devShell 放入 `pkgs.uv` 和选定 Python，以 `uv sync` / `uv run`
使用项目环境。PyPI 原生 wheel 可能需要额外系统库；逐项验证，避免
无条件设置全局 `LD_LIBRARY_PATH`。

Nix 管理 editable 环境时，在生产 Python set 之上单独覆盖：

```nix
editable-python-set = python-set.overrideScope (
  workspace.mkEditablePyprojectOverlay { root = "$REPO_ROOT"; }
);
dev-environment = editable-python-set.mkVirtualEnv "example-dev" workspace.deps.all;
```

将开发环境与 uv 放入 `mkShell.packages`，设置 `UV_NO_SYNC=1`、
`UV_PYTHON=editable-python-set.python.interpreter`、
`UV_PYTHON_DOWNLOADS=never`。shellHook 清除继承的 `PYTHONPATH`，
并将 `REPO_ROOT` 设为本地仓库根目录；如需在无 Git 的源码目录工作，
提供与项目实际布局匹配的回退。不要将 editable overlay 用于发布包。

这种环境中直接使用 Nix 提供的 Python/入口命令；若当前用户要求通过
`uv run` 执行，优先选择简单 devShell。保留已有 editable 工作流时，
确认 uv 使用的是 Nix 提供的环境，验证 `sys.executable`，避免误用
仓库里的旧 `.venv`。

## 运行时适配

- 外部命令通过 wrapper 指向 Nix store 中的可执行文件。应用已有可配置
  命令变量时，可用 `makeWrapper` 的 `--set-default` 提供可覆盖默认值；
  需要按名称发现多个命令时，为应用 wrapper 设置必要的 `PATH`。
- 通过 `ctypes` 等动态加载的库可能无法被 `autoPatchelf` 发现。检查
  实际加载代码，必要时将查找结果补丁为 Nix store 的库路径，并用
  `pkgs.stdenv.hostPlatform.extensions.sharedLibrary` 选择共享库扩展名。
- 后端与代理等独立入口若需要不同 extras，分别构建生产环境，避免
  所有用户都安装完整依赖集合。为每个入口提供明确的 app 和相应检查。

## 上游资料

优先读取目标 flake 锁定的源码；需要联网查接口时使用官方来源：

- [uv2nix getting started](https://pyproject-nix.github.io/uv2nix/usage/getting-started.html)
- [uv2nix 源码与模板](https://github.com/pyproject-nix/uv2nix)
- [pyproject.nix mkApplication](https://pyproject-nix.github.io/pyproject.nix/build/util.html)
- [build-system-pkgs](https://github.com/pyproject-nix/build-system-pkgs)
