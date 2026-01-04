# 使用官方 Go 镜像 (Debian Bookworm)
FROM golang:bookworm

# 设置非交互模式
ENV DEBIAN_FRONTEND=noninteractive

# 1. 安装基础工具 (注意：这里去掉了 upx，加上了 xz-utils)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    git \
    zip \
    unzip \
    xz-utils \
    build-essential \
    mingw-w64 \
    gcc-aarch64-linux-gnu \
    gcc-arm-linux-gnueabi \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 2. 手动安装 UPX (因为 Debian Bookworm 源里没有 upx)
# 下载官方发布版 -> 解压 -> 移动到 /usr/bin -> 清理
RUN curl -L -o upx.tar.xz https://github.com/upx/upx/releases/download/v5.0.2/upx-5.0.2-amd64_linux.tar.xz && \
    tar -xf upx.tar.xz && \
    mv upx-5.0.2-amd64_linux/upx /usr/bin/upx && \
    chmod +x /usr/bin/upx && \
    rm -rf upx.tar.xz upx-5.0.2-amd64_linux

# 3. 安装 GitHub CLI (gh) 用于上传 Release
RUN mkdir -p -m 755 /etc/apt/keyrings && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null && \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && \
    apt-get install -y gh && \
    rm -rf /var/lib/apt/lists/*

# 复制入口脚本
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]