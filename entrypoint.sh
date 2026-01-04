#!/bin/bash
set -e

# === 0. 辅助函数：标准化布尔值 ===
to_bool() {
    local val=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    if [[ "$val" == "true" || "$val" == "1" ]]; then echo "true"; else echo "false"; fi
}

BOOL_CGO=$(to_bool "${INPUT_CGO}")
BOOL_UPX=$(to_bool "${INPUT_UPX}")
BOOL_MD5=$(to_bool "${INPUT_MD5}")
BOOL_SHA256=$(to_bool "${INPUT_SHA256}")
BOOL_OVERWRITE=$(to_bool "${INPUT_OVERWRITE}")
BOOL_CACHE=$(to_bool "${INPUT_CACHE}")

# 防止 Git 目录报错
git config --global --add safe.directory /github/workspace

# === 1. 初始化与版本检测 ===
PROJECT_DIR="/github/workspace/${INPUT_PROJECT_PATH}"
if [ ! -d "$PROJECT_DIR" ]; then
    echo "Error: Project directory '$PROJECT_DIR' does not exist."
    exit 1
fi

# 提取版本号
VERSION="${INPUT_RELEASE_TAG}"
if [ -z "$VERSION" ]; then
    if [[ "$GITHUB_REF" == refs/tags/* ]]; then
        VERSION="${GITHUB_REF#refs/tags/}"
    elif [[ "$GITHUB_REF" == refs/heads/* ]]; then
        VERSION="${GITHUB_REF#refs/heads/}"
    else
        VERSION="unknown"
    fi
fi
echo "ℹ️  Version detected: $VERSION"

cd "$PROJECT_DIR"

# === 2. 动态安装 Go (如果指定) ===
if [ -n "${INPUT_GO_VERSION}" ] && [ "${INPUT_GO_VERSION}" != "latest" ]; then
    echo "⬇️  Switching Go version to: ${INPUT_GO_VERSION}..."
    URL="https://go.dev/dl/go${INPUT_GO_VERSION}.linux-amd64.tar.gz"
    curl -L -o go_custom.tar.gz "$URL"
    rm -rf /usr/local/go && tar -C /usr/local -xzf go_custom.tar.gz
    rm go_custom.tar.gz
    export PATH="/usr/local/go/bin:$PATH"
    echo "✅ Go version updated:"
    go version
else
    echo "ℹ️  Using default Go version."
fi

# === 3. 缓存配置 (新增核心逻辑) ===
if [ "$BOOL_CACHE" == "true" ]; then
    echo "⚡ Cache enabled: Redirecting GOCACHE and GOMODCACHE to workspace..."
    # 将缓存重定向到 workspace 下的隐藏目录，这样外部 actions/cache 才能访问到
    export GOCACHE="/github/workspace/.cache/go-build"
    export GOMODCACHE="/github/workspace/.cache/go-mod"
    mkdir -p "$GOCACHE"
    mkdir -p "$GOMODCACHE"
else
    echo "ℹ️  Cache disabled."
fi

# === 4. 处理依赖 ===
if [ -f "go.mod" ]; then
    echo "📦 Resolving dependencies (go mod tidy)..."
    go mod tidy
else
    echo "⚠️  No go.mod found, skipping go mod tidy."
fi

# === 5. 编译环境配置 ===
export GOOS="${INPUT_GOOS}"
export GOARCH="${INPUT_GOARCH}"
export CGO_ENABLED=0

if [ "$BOOL_CGO" == "true" ]; then
    export CGO_ENABLED=1
    echo "🔧 CGO Enabled. Configuring cross-compiler..."
    
    export CC="gcc"
    export CXX="g++"

    if [ "$GOOS" == "windows" ] && [ "$GOARCH" == "amd64" ]; then
        export CC="x86_64-w64-mingw32-gcc"
        export CXX="x86_64-w64-mingw32-g++"
    elif [ "$GOOS" == "windows" ] && [ "$GOARCH" == "386" ]; then
        export CC="i686-w64-mingw32-gcc"
        export CXX="i686-w64-mingw32-g++"
    elif [ "$GOOS" == "linux" ] && [ "$GOARCH" == "arm64" ]; then
        export CC="aarch64-linux-gnu-gcc"
        export CXX="aarch64-linux-gnu-g++"
    elif [ "$GOOS" == "linux" ] && [ "$GOARCH" == "arm" ]; then
        export CC="arm-linux-gnueabi-gcc"
        export CXX="arm-linux-gnueabi-g++"
    fi
    
    echo "   -> Compiler: $CC"
    
    if [ "$GOOS" == "linux" ]; then
        INPUT_LDFLAGS="${INPUT_LDFLAGS} -extldflags \"-static\""
    fi
else
    echo "🛡️ CGO Disabled."
fi

BINARY_NAME="${INPUT_BINARY_NAME}"
if [ "$GOOS" == "windows" ]; then
    BINARY_NAME="${BINARY_NAME}.exe"
fi

# === 6. 执行构建 ===
echo "🔨 Building ${BINARY_NAME}..."
go build -v -a \
  -ldflags "${INPUT_LDFLAGS}" \
  ${INPUT_EXTRA_FLAGS} \
  -o "${BINARY_NAME}" \
  .

if [ ! -f "${BINARY_NAME}" ]; then
    echo "❌ Build failed!"
    exit 1
fi

# === 7. UPX 压缩 ===
if [ "$BOOL_UPX" == "true" ]; then
    echo "📦 Compressing with UPX..."
    upx ${INPUT_UPX_ARGS} "${BINARY_NAME}" || echo "⚠️ UPX skipped (error or unsupported arch)."
fi

# === 8. 打包与命名 ===
FINAL_NAME="${INPUT_BINARY_NAME}-${VERSION}-${INPUT_GOOS}-${INPUT_GOARCH}"
PACKED_FILE=""
COMPRESS_TYPE="${INPUT_COMPRESS_ASSETS}"

if [ "$COMPRESS_TYPE" == "auto" ]; then
    if [ "$GOOS" == "windows" ]; then COMPRESS_TYPE="zip"; else COMPRESS_TYPE="tar.gz"; fi
fi

if [ "$COMPRESS_TYPE" == "zip" ]; then
    PACKED_FILE="${FINAL_NAME}.zip"
    echo "🗜️ Zipping to ${PACKED_FILE}..."
    zip -r "${PACKED_FILE}" "${BINARY_NAME}"
elif [ "$COMPRESS_TYPE" == "tar.gz" ]; then
    PACKED_FILE="${FINAL_NAME}.tar.gz"
    echo "🗜️ Tarballing to ${PACKED_FILE}..."
    tar -czvf "${PACKED_FILE}" "${BINARY_NAME}"
else
    PACKED_FILE="${FINAL_NAME}"
    if [ "$GOOS" == "windows" ]; then PACKED_FILE="${PACKED_FILE}.exe"; fi
    mv "${BINARY_NAME}" "${PACKED_FILE}"
    echo "⏩ Renamed binary to ${PACKED_FILE}"
fi

# === 9. 生成 Hash ===
FILES_TO_UPLOAD="${PACKED_FILE}"
if [ "$BOOL_MD5" == "true" ]; then
    md5sum "${PACKED_FILE}" > "${PACKED_FILE}.md5"
    FILES_TO_UPLOAD="$FILES_TO_UPLOAD ${PACKED_FILE}.md5"
fi
if [ "$BOOL_SHA256" == "true" ]; then
    sha256sum "${PACKED_FILE}" > "${PACKED_FILE}.sha256"
    FILES_TO_UPLOAD="$FILES_TO_UPLOAD ${PACKED_FILE}.sha256"
fi

if [ "$PROJECT_DIR" != "/github/workspace" ]; then
    cp $FILES_TO_UPLOAD /github/workspace/
fi

# === 10. Release 上传 ===
if [ -n "${INPUT_GITHUB_TOKEN}" ]; then
    echo "🚀 Uploading to Release: $VERSION"
    export GITHUB_TOKEN="${INPUT_GITHUB_TOKEN}"
    if [ -z "$VERSION" ] || [ "$VERSION" == "unknown" ]; then
        echo "⚠️  No tag detected, skipping upload."
    else
        UPLOAD_OPTS=""
        if [ "$BOOL_OVERWRITE" == "true" ]; then UPLOAD_OPTS="--clobber"; fi
        gh release upload "$VERSION" $FILES_TO_UPLOAD $UPLOAD_OPTS || echo "❌ Upload failed."
    fi
else
    echo "ℹ️  No token provided, skipping upload."
fi