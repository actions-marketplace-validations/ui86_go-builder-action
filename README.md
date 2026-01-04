# Go Build, UPX & Release Action

**全能型 Go 语言构建与发布 Action**。支持交叉编译、UPX 自动压缩、资产打包、哈希校验、构建缓存，并自动上传到 GitHub Releases。

旨在简化 Go 项目的发布流程，只需一个步骤即可完成从源码到 Release 发布的全部工作。

## ✨ 核心功能

* 🚀 **交叉编译**：一键构建 Windows, Linux, macOS (Darwin) 的二进制文件。
* 📦 **UPX 压缩**：内置 UPX 工具，支持高压缩比，大幅减小体积。
* 🛠 **CGO 支持**：内置 MinGW 和 GCC 交叉编译器，完美支持 CGO (如 `go-sqlite3`) 编译 Windows/Linux 版。
* ⚡️ **构建缓存**：支持 `go-build` 和 `go-mod` 缓存，显著提升二次构建速度。
* 🔒 **安全校验**：自动生成 MD5 和 SHA256 校验文件。
* 📤 **自动发布**：集成 GitHub CLI，自动将构建产物上传到 GitHub Releases。
* 🎨 **灵活配置**：支持自定义 Go 版本、编译参数 (`ldflags`)、打包格式 (`zip`/`tar.gz`) 等。

---

## 📖 快速开始

### 基础用法

在你的 `.github/workflows/release.yml` 中添加以下步骤：

```yaml
name: Release

on:
  release:
    types: [created]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build and Publish
        uses: ui86/go-builder-action@v1
        with:
          binary_name: 'myapp'
          github_token: ${{ secrets.GITHUB_TOKEN }}

```

---

## 🔥 高级用法

### 1. 矩阵构建 (Matrix Build) - 推荐

同时发布 Windows, Linux, macOS 版本，并自动压缩和上传。

```yaml
jobs:
  release-matrix:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        goos: [linux, windows, darwin]
        goarch: [amd64, arm64]
        exclude:
          - goos: windows
            goarch: arm64
          - goos: darwin
            goarch: "386"
    steps:
      - uses: actions/checkout@v4

      - name: Build & Upload
        uses: ui86/go-builder-action@v1
        with:
          binary_name: 'myapp'
          goos: ${{ matrix.goos }}
          goarch: ${{ matrix.goarch }}
          go_version: '1.21'   # 指定 Go 版本
          upx: true            # 开启压缩
          compress_assets: auto # Windows转zip，其他转tar.gz
          md5: true
          sha256: true
          github_token: ${{ secrets.GITHUB_TOKEN }}

```

### 2. CGO 支持 (例如 SQLite)

本 Action 内置了 `mingw-w64` 和 `gcc-aarch64` 等交叉编译器。

```yaml
      - name: Build Windows with SQLite
        uses: ui86/go-builder-action@v1
        with:
          binary_name: 'myapp-sqlite'
          goos: 'windows'
          goarch: 'amd64'
          cgo: true  # <--- 开启 CGO，自动使用 MinGW 编译器
          # 针对 SQLite 的常见静态链接参数
          extra_flags: '-tags "sqlite_omit_load_extension netgo osusergo"' 
          github_token: ${{ secrets.GITHUB_TOKEN }}

```

### 3. 启用构建缓存 (加速构建)

配合 `actions/cache` 使用，将 Go 的缓存目录映射出来。

```yaml
    steps:
      - uses: actions/checkout@v4

      # 1. 配置缓存恢复
      - name: Restore Go Cache
        uses: actions/cache@v3
        with:
          path: |
            .cache/go-build
            .cache/go-mod
          key: ${{ runner.os }}-go-${{ hashFiles('**/go.sum') }}
          restore-keys: ${{ runner.os }}-go-

      # 2. 开启 Action 的缓存开关
      - name: Build with Cache
        uses: ui86/go-builder-action@v1
        with:
          binary_name: 'myapp'
          cache: true  # <--- 关键：告诉 Action 使用外部缓存目录
          github_token: ${{ secrets.GITHUB_TOKEN }}

```

---

## ⚙️ 参数说明 (Inputs)

| 参数名 | 必填 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `binary_name` | ✅ | - | 生成的二进制文件名 |
| `github_token` | ❌ | - | 用于上传 Release，通常传 `${{ secrets.GITHUB_TOKEN }}` |
| `project_path` | ❌ | `.` | Go 项目所在的子目录 |
| `go_version` | ❌ | latest | 指定 Go 版本 (如 `1.21.5`)，留空则使用镜像最新版 |
| `goos` | ❌ | `linux` | 目标操作系统 (linux, windows, darwin) |
| `goarch` | ❌ | `amd64` | 目标架构 (amd64, arm64, 386, arm) |
| `cgo` | ❌ | `false` | 是否开启 CGO (支持 Windows/Linux 交叉编译) |
| `ldflags` | ❌ | `-s -w` | 编译参数，默认去除符号表以减小体积 |
| `extra_flags` | ❌ | - | 额外的 `go build` 参数 (如 `-tags prod`) |
| `upx` | ❌ | `true` | 是否使用 UPX 压缩二进制文件 |
| `upx_args` | ❌ | `--best --lzma` | UPX 压缩参数 |
| `compress_assets` | ❌ | `auto` | 打包格式: `auto`, `zip`, `tar.gz`, `false` |
| `md5` | ❌ | `true` | 是否生成 MD5 校验文件 |
| `sha256` | ❌ | `true` | 是否生成 SHA256 校验文件 |
| `release_tag` | ❌ | auto | 指定发布的 Tag，默认自动从 Trigger 获取 |
| `overwrite` | ❌ | `true` | 是否覆盖 Release 中已存在的同名文件 |
| `cache` | ❌ | `false` | 是否将缓存重定向到 workspace 以便持久化 |

---

## 📦 输出产物 (Artifacts)

Action 将生成以下格式的文件并上传到 GitHub Release：

* **压缩包**: `<binary>-<version>-<os>-<arch>.<zip|tar.gz>`
* **校验和**: `<filename>.md5`, `<filename>.sha256`

例如: `myapp-v1.0.0-linux-amd64.tar.gz`

---

## 🛠 本地开发与测试

如果你想修改此 Action 或进行本地测试：

1. 克隆仓库。
2. 确保 `test/` 目录下有 `main.go` 和 `go.mod`。
3. 运行测试 Workflow：
```bash
# 需要安装 https://github.com/nektos/act
act push -j test-build

```



---

## 📄 License

MIT License © 2026 [UI86]