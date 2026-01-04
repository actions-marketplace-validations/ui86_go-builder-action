#!/bin/bash
set -e

# 防止 Git 目录归属权报错
git config --global --add safe.directory /github/workspace

# === 1. 初始化路径 ===
PROJECT_DIR="/github/workspace/${INPUT_PROJECT_PATH}"
if [ ! -d "$PROJECT_DIR" ]; then
    echo "Error: Project directory '$PROJECT_DIR' does not exist."
    exit 1
fi
cd "$PROJECT_DIR"

# === 2. 配置环境 ===
export GOOS="${INPUT_GOOS}"
export GOARCH="${INPUT_GOARCH}"

# 动态配置 CGO 和 编译器
if [ "${INPUT_CGO}" == "true" ]; then
    export CGO_ENABLED=1
    echo "🔧 CGO Enabled. Configuring cross-compiler..."
    
    export CC="gcc"
    export CXX="g++"

    # Windows 64-bit
    if [ "$GOOS" == "windows" ] && [ "$GOARCH" == "amd64" ]; then
        export CC="x86_64-w64-mingw32-gcc"
        export CXX="x86_64-w64-mingw32-g++"
    # Windows 32-bit
    elif [ "$GOOS" == "windows" ] && [ "$GOARCH" == "386" ]; then
        export CC="i686-w64-mingw32-gcc"
        export CXX="i686-w64-mingw32-g++"
    # Linux ARM64
    elif [ "$GOOS" == "linux" ] && [ "$GOARCH" == "arm64" ]; then
        export CC="aarch64-linux-gnu-gcc"
        export CXX="aarch64-linux-gnu-g++"
    # Linux ARM
    elif [ "$GOOS" == "linux" ] && [ "$GOARCH" == "arm" ]; then
        export CC="arm-linux-gnueabi-gcc"
        export CXX="arm-linux-gnueabi-g++"
    fi
    
    echo "   -> Compiler set to: $CC"
    
    # CGO Linux 静态链接修复
    if [ "$GOOS" == "linux" ]; then
        INPUT_LDFLAGS="${INPUT_LDFLAGS} -extldflags \"-static\""
    fi
else
    export CGO_ENABLED=0
    echo "🛡️ CGO Disabled."
fi

# 处理 Windows 后缀
BINARY_NAME="${INPUT_BINARY_NAME}"
if [ "$GOOS" == "windows" ]; then
    BINARY_NAME="${BINARY_NAME}.exe"
fi

# === 3. 执行编译 ===
echo "🔨 Building ${BINARY_NAME} for ${GOOS}/${GOARCH}..."
go build -v -a \
  -ldflags "${INPUT_LDFLAGS}" \
  ${INPUT_EXTRA_FLAGS} \
  -o "${BINARY_NAME}" \
  .

if [ ! -f "${BINARY_NAME}" ]; then
    echo "❌ Build failed: ${BINARY_NAME} not created."
    exit 1
fi

# === 4. UPX 压缩 ===
if [ "${INPUT_ENABLE_UPX}" == "true" ]; then
    echo "📦 Compressing with UPX..."
    upx ${INPUT_UPX_ARGS} "${BINARY_NAME}" || echo "⚠️ UPX failed or skipped (arch unsupported?), continuing..."
fi

# === 5. 资产打包 ===
ASSET_NAME="${INPUT_BINARY_NAME}-${INPUT_GOOS}-${INPUT_GOARCH}"
PACKED_FILE=""
COMPRESS_TYPE="${INPUT_COMPRESS_ASSETS}"

if [ "$COMPRESS_TYPE" == "auto" ]; then
    if [ "$GOOS" == "windows" ]; then COMPRESS_TYPE="zip"; else COMPRESS_TYPE="tar.gz"; fi
fi

if [ "$COMPRESS_TYPE" == "zip" ]; then
    PACKED_FILE="${ASSET_NAME}.zip"
    echo "🗜️ Zipping to ${PACKED_FILE}..."
    zip -r "${PACKED_FILE}" "${BINARY_NAME}"
elif [ "$COMPRESS_TYPE" == "tar.gz" ]; then
    PACKED_FILE="${ASSET_NAME}.tar.gz"
    echo "🗜️ Tarballing to ${PACKED_FILE}..."
    tar -czvf "${PACKED_FILE}" "${BINARY_NAME}"
else
    PACKED_FILE="${BINARY_NAME}" # 不压缩
    echo "⏩ Skipping archive."
fi

# === 6. 生成 Hash ===
FILES_TO_UPLOAD="${PACKED_FILE}"

if [ "${INPUT_MD5}" == "true" ]; then
    md5sum "${PACKED_FILE}" > "${PACKED_FILE}.md5"
    FILES_TO_UPLOAD="$FILES_TO_UPLOAD ${PACKED_FILE}.md5"
fi

if [ "${INPUT_SHA256}" == "true" ]; then
    sha256sum "${PACKED_FILE}" > "${PACKED_FILE}.sha256"
    FILES_TO_UPLOAD="$FILES_TO_UPLOAD ${PACKED_FILE}.sha256"
fi

# 移动到根目录方便 Debug（如果是在子目录编译）
if [ "$PROJECT_DIR" != "/github/workspace" ]; then
    cp $FILES_TO_UPLOAD /github/workspace/
fi

# === 7. 上传到 Release ===
if [ -n "${INPUT_GITHUB_TOKEN}" ]; then
    echo "🚀 Uploading to GitHub Release..."
    export GITHUB_TOKEN="${INPUT_GITHUB_TOKEN}"
    
    TAG_NAME="${INPUT_RELEASE_TAG}"
    # 如果没指定 Tag，尝试从 Ref 获取
    if [ -z "$TAG_NAME" ]; then
        if [[ "$GITHUB_REF" == refs/tags/* ]]; then
            TAG_NAME="${GITHUB_REF#refs/tags/}"
        fi
    fi

    if [ -z "$TAG_NAME" ]; then
        echo "⚠️ No tag found. Skipping upload."
    else
        UPLOAD_OPTS=""
        if [ "${INPUT_OVERWRITE}" == "true" ]; then UPLOAD_OPTS="--clobber"; fi
        
        # 真正执行上传
        gh release upload "$TAG_NAME" $FILES_TO_UPLOAD $UPLOAD_OPTS || echo "❌ Upload failed (Does release exist?)."
    fi
else
    echo "ℹ️ GITHUB_TOKEN not provided. Skipping upload."
fi