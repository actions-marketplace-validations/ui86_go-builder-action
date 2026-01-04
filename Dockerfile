# 使用官方 Go 镜像 (Debian Bookworm)
FROM golang:1.22-bookworm

# 设置非交互模式
ENV DEBIAN_FRONTEND=noninteractive

# 1. 安装基础工具、C 交叉编译器、UPX
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    git \
    zip \
    unzip \
    upx-ucl \
    build-essential \
    mingw-w64 \
    gcc-aarch64-linux-gnu \
    gcc-arm-linux-gnueabi \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 2. 安装 GitHub CLI (gh) 用于上传 Release
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