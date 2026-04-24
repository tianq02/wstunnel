# ccr.ccs.tencentyun.com/tianq/wstunnel:v10.5.2.fix

ARG BUILDER_IMAGE=builder_cache

############################################################
# Cache image with all the deps
FROM docker.1ms.run/library/rust:1.93-trixie AS builder_cache

RUN rustup component add rustfmt clippy && apt-get update && apt-get install cmake libclang-dev -y

WORKDIR /build
COPY . ./

# setup rust mirror
RUN <<EOF
    echo 'export RUSTUP_DIST_SERVER="https://rsproxy.cn"' >> ~/.bashrc
    echo 'export RUSTUP_UPDATE_ROOT="https://rsproxy.cn/rustup"' >> ~/.bashrc
    mkdir -p ~/.cargo
    cat > ~/.cargo/config <<'CONFIG'
[source.crates-io]
replace-with = "rsproxy-sparse"

[source.rsproxy]
registry = "https://rsproxy.cn/crates.io-index"

[source.rsproxy-sparse]
registry = "sparse+https://rsproxy.cn/index/"

[registries.rsproxy]
index = "https://rsproxy.cn/crates.io-index"

[net]
git-fetch-with-cli = true
CONFIG
EOF

RUN cargo fmt --all -- --check --color=always || (echo "Use cargo fmt to format your code"; exit 1)
#RUN cargo clippy --all -- -D warnings || (echo "Solve your clippy warnings to succeed"; exit 1)

#RUN cargo test --all --all-features
#RUN just test "tcp://localhost:2375" || (echo "Test are failing"; exit 1)

#ENV RUSTFLAGS="-C link-arg=-Wl,--compress-debug-sections=zlib -C force-frame-pointers=yes"
RUN cargo build --tests
#RUN cargo build --release --all-features


############################################################
# Builder for production image
FROM ${BUILDER_IMAGE} AS builder_release

WORKDIR /build
COPY . ./

ARG BIN_TARGET=--bins
ARG PROFILE=release

#ENV RUSTFLAGS="-C link-arg=-Wl,--compress-debug-sections=zlib -C force-frame-pointers=yes"
RUN cargo build --features=jemalloc --profile=${PROFILE} ${BIN_TARGET}


############################################################
# Final image
FROM docker.1ms.run/library/debian:trixie-slim AS final-image

RUN useradd -ms /bin/bash app && \
        apt-get update && \
        apt-get -y upgrade && \
        apt install -y --no-install-recommends ca-certificates dumb-init && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists

WORKDIR /home/app

ARG PROFILE=release
COPY --from=builder_release  /build/target/${PROFILE}/wstunnel wstunnel

ENV RUST_LOG="INFO"
ENV SERVER_PROTOCOL="wss"
ENV SERVER_LISTEN="[::]"
ENV SERVER_PORT="8080"
EXPOSE 8080

USER app

ENTRYPOINT ["/usr/bin/dumb-init", "-v", "--"]
CMD ["/bin/sh", "-c", "exec /home/app/wstunnel server ${SERVER_PROTOCOL}://${SERVER_LISTEN}:${SERVER_PORT}"]
