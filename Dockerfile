# syntax=docker/dockerfile:1
FROM stagex/pallet-rust@sha256:9c38bf1066dd9ad1b6a6b584974dd798c2bf798985bf82e58024fbe0515592ca AS pallet-rust
FROM stagex/user-protobuf@sha256:5e67b3d3a7e7e9db9aa8ab516ffa13e54acde5f0b3d4e8638f79880ab16da72c AS protobuf 
FROM stagex/user-abseil-cpp@sha256:3dca99adfda0cb631bd3a948a99c2d5f89fab517bda034ce417f222721115aa2 AS abseil-cpp
# jq allows us to parse `cargo metadata` json outputs
FROM stagex/user-jq@sha256:0c75672e97f54b83661aaa498e053340305e79cdc2004a40d92b7bf5ce906e9c AS jq-shim
# bash allows us to iterate over the names from `cargo metadata`
FROM stagex/core-bash@sha256:6217a843ac51eb8073c3cf13be7d4d1cc9e28f7d7a1f9fd23feb0caa604f73bf AS bash-shim

# --- Stage 1: Build with Rust --- (amd64)
FROM pallet-rust AS builder
COPY --from=protobuf . /
COPY --from=abseil-cpp . /
COPY --from=jq-shim . /
COPY --from=bash-shim . /

ENV SOURCE_DATE_EPOCH=1
# ENV CXXFLAGS="-include cstdint" #needed?
# ENV ROCKSDB_USE_PKG_CONFIG=0 # not needed
ENV CARGO_HOME=/usr/local/cargo

WORKDIR /usr/src/app
# Copy the entire workspace to include all crates
COPY . .

# print backtrace w panic, useful for development only?
ENV RUST_BACKTRACE=1
ENV RUSTFLAGS="-C codegen-units=1"
# enables the C runtime to be linked statically w/ linux musl
ENV RUSTFLAGS="${RUSTFLAGS} -C target-feature=+crt-static"
# disables build ID in final binary by linker wrapper flag
ENV RUSTFLAGS="${RUSTFLAGS} -C link-arg=-Wl,--build-id=none"
# any GCC version passes
ENV CFLAGS="-D__GNUC_PREREQ(maj,min)=1"
ENV TARGET_ARCH="x86_64-unknown-linux-musl"

# testing
# RUN openssl s_client -connect index.crates.io:443 -servername index.crates.io
# RUN wget https://index.crates.io/config.json
# RUN ls -la ~/.cargo/ || echo "No .cargo dir"
# RUN cat ~/.cargo/config || echo "No config"

# This caches Cargo’s registry and git dependencies.
# If Cargo.toml changes and invalidates the layer, the next build still reuses the cached crates instead of redownloading them.
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    cargo fetch --locked --target $TARGET_ARCH

#  if Cargo.toml has changed (e.g., new dependencies), but Cargo.lock hasn't been updated, the build fails
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    cargo metadata --locked --format-version=1 > /dev/null 2>&1


# build all dependent crates in release mode
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/usr/src/app/target \
    --network=none \
    cargo build --release --frozen \
      # builds all members in the workspace
      --workspace \
      --target ${TARGET_ARCH} \
      # currently building only with all features.
      --all-features

# Parse workspace and output dry-run publish commands
SHELL ["/bin/bash", "-c"]
# RUN for name in $(cargo metadata --format-version 1 --no-deps --all-features | jq -r '.packages[].name'); do echo "Publishing: $name"; RUSTFLAGS="-C target-feature=-crt-static" cargo publish -p "$name" --dry-run; done
RUN for name in $(cargo metadata --format-version 1 --no-deps --all-features | jq -r '.packages[].name'); do echo "Publishing: $name"; cargo publish -p "$name" --dry-run; done
RUN ls -la

# --- Stage 2: layer for local extraction ---
# FROM scratch AS export

# 
# COPY --from=builder /usr/src/app/.../etc /exported
