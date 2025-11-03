# ==============================
# Builder
# ==============================
FROM --platform=$BUILDPLATFORM ubuntu:20.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive \
    CCACHE_DIR=/ccache \
    CCACHE_BASEDIR=/build_context \
    CCACHE_NOHASHDIR=1 \
    CCACHE_COMPILERCHECK='%compiler% --version'

# 安装依赖（同前）
RUN apt-get update && \
    apt-get install -y \
        wget ca-certificates gnupg software-properties-common git \
        cmake ninja-build python3 \
        libicu-dev libssl-dev libkrb5-dev libsparsehash-dev \
        curl sudo less ccache && \
    wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add - && \
    add-apt-repository "deb http://apt.llvm.org/focal/ llvm-toolchain-focal-16 main" && \
    apt-get update && \
    apt-get install -y clang-16 lld-16 llvm-16-dev && \
    update-alternatives --install /usr/bin/clang clang /usr/bin/clang-16 100 && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-16 100 && \
    update-alternatives --install /usr/bin/ld.lld ld.lld /usr/bin/ld.lld-16 100 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 将整个构建上下文（即 ClickHouse 源码）复制到 /build_context
COPY . /build_context

WORKDIR /build_context

# 现在 /build_context 应包含 CMakeLists.txt
RUN ls -l CMakeLists.txt  # 可用于调试

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
# Runtime
# ==============================
FROM ubuntu:20.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y libicu66 libssl1.1 libkrb5-3 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN groupadd -r clickhouse && useradd -r -g clickhouse clickhouse

WORKDIR /var/lib/clickhouse
COPY --from=builder /build_context/build/programs/clickhouse /usr/bin/clickhouse
RUN chmod +x /usr/bin/clickhouse && \
    chown -R clickhouse:clickhouse /var/lib/clickhouse

EXPOSE 8123 9000 9009
USER clickhouse
ENTRYPOINT ["/usr/bin/clickhouse", "server"]
