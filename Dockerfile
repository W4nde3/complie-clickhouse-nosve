# ==============================
# Builder Stage (aarch64 cross-compile)
# ==============================
FROM --platform=$BUILDPLATFORM ubuntu:20.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV CCACHE_DIR=/ccache
ENV CCACHE_BASEDIR=/src
ENV CCACHE_NOHASHDIR=1
ENV CCACHE_COMPILERCHECK='%compiler% --version'

# 安装依赖（v24.3 LTS 要求 Clang >=16，CMake >=3.20）
RUN apt-get update && \
    apt-get install -y \
        git \
        wget \
        ca-certificates \
        gnupg \
        software-properties-common && \
    # 添加 LLVM 官方 APT 仓库（获取 Clang 16）
    wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add - && \
    add-apt-repository "deb http://apt.llvm.org/focal/ llvm-toolchain-focal-16 main" && \
    apt-get update && \
    apt-get install -y \
        cmake \
        ninja-build \
        clang-16 \
        lld-16 \
        llvm-16-dev \
        python3 \
        libicu-dev \
        libssl-dev \
        libkrb5-dev \
        libsparsehash-dev \
        ccache \
        curl \
        sudo \
        less && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 设置 clang-16 为默认
RUN update-alternatives --install /usr/bin/clang clang /usr/bin/clang-16 100 && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-16 100 && \
    update-alternatives --install /usr/bin/ld.lld ld.lld /usr/bin/ld.lld-16 100

WORKDIR /src
# 源码已由 GitHub Actions 挂载进来

# 构建
RUN --mount=type=cache,target=/ccache \
    mkdir -p build && \
    cd build && \
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_SVE=OFF \
        -DENABLE_DOT=ON \
        -DENABLE_FCMA=ON \
        -DARCH_NATIVE=OFF \
        -DCMAKE_C_COMPILER=clang \
        -DCMAKE_CXX_COMPILER=clang++ \
        -DCOMPILER_CACHE=ccache && \
    cmake --build . --target clickhouse -- -j$(nproc)

# ==============================
# Runtime Stage
# ==============================
FROM ubuntu:20.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y \
        libicu66 \
        libssl1.1 \
        libkrb5-3 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN groupadd -r clickhouse && useradd -r -g clickhouse clickhouse

WORKDIR /var/lib/clickhouse
COPY --from=builder /src/build/programs/clickhouse /usr/bin/clickhouse
RUN chmod +x /usr/bin/clickhouse && \
    chown -R clickhouse:clickhouse /var/lib/clickhouse

EXPOSE 8123 9000 9009
USER clickhouse
ENTRYPOINT ["/usr/bin/clickhouse", "server"]
