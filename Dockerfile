# syntax=docker/dockerfile:1
FROM stagex/pallet-rust@sha256:4062550919db682ebaeea07661551b5b89b3921e3f3a2b0bc665ddea7f6af1ca AS pallet-rust
FROM stagex/user-protobuf@sha256:b399bb058216a55130d83abcba4e5271d8630fff55abbb02ed40818b0d96ced1 AS protobuf
FROM stagex/user-abseil-cpp@sha256:926f69e9cd112dfe3450a0af56d1560dc0a62589e61047e8c92c3b7edf8dd71e AS abseil-cpp
# jq allows us to parse `cargo metadata` json outputs
FROM stagex/user-jq@sha256:1b551175e7507d1a5d3564c01d6d0c458aa2be0172e03ccec8d2263e217c4c78 AS jq-shim
# bash allows us to iterate over the names from `cargo metadata`
FROM stagex/core-bash@sha256:5b598c14eef61148baf3f5a2830a214a5985b5d3544b019e3d0ed53c6b66989a AS bash-shim

# --- Stage 0 get the package dependency order

# FROM pallet-rust AS json_output
# 
# ENV SOURCE_DATE_EPOCH=1
# ENV CARGO_HOME=/usr/local/cargo
# WORKDIR /usr/src/app
# 
# # Copy the entire workspace to include all crates
# COPY . .
# 
# # print backtrace w panic, useful for development only?
# ENV RUST_BACKTRACE=1
# ENV RUSTFLAGS="-C codegen-units=1"
# 
# # test for clobber
# # ENV CXX=foo
# # RUN echo $CXX
# 
# RUN cargo install cargo-workspaces
# RUN cargo workspaces plan --json > ordered_crate_list.json

# --- Stage 1: Build with Rust --- (amd64)

FROM pallet-rust AS builder
COPY --from=protobuf . /
COPY --from=abseil-cpp . /
COPY --from=jq-shim . /
# COPY --from=bash-shim . /

ENV SOURCE_DATE_EPOCH=1
# ENV ROCKSDB_USE_PKG_CONFIG=0 # not needed
ENV CARGO_HOME=/usr/local/cargo
# target dir to output all crates into a single directory
ENV CARGO_TARGET_DIR=/usr/src/app/output_crates
RUN mkdir -p /usr/src/app/output_crates

WORKDIR /usr/src/app
# Copy the entire workspace to include all crates
COPY . .
# COPY --from=json_output /usr/src/app/ordered_crate_list.json /usr/src/app/ocl.json

# RUN pwd
# RUN ls -lat *.json
# RUN cat ocl.json

#needed?
# ENV CXXFLAGS="-include cstdint"
# print backtrace w panic, useful for development only?
ENV RUST_BACKTRACE=1
ENV RUSTFLAGS="-C codegen-units=1"
# enables the C runtime to be linked statically w/ linux musl ?
ENV RUSTFLAGS="${RUSTFLAGS} -C target-feature=+crt-static"
# disables build ID in final binary by linker wrapper flag
ENV RUSTFLAGS="${RUSTFLAGS} -C link-arg=-Wl,--build-id=none"
# any GCC version passes
ENV CFLAGS="-D__GNUC_PREREQ(maj,min)=1"
ENV TARGET_ARCH="x86_64-unknown-linux-musl"

# This caches Cargo’s registry and git dependencies.
# If Cargo.toml changes and invalidates the layer, the next build still reuses the cached crates instead of redownloading them.
 RUN --mount=type=cache,target=/usr/local/cargo/registry \
     --mount=type=cache,target=/usr/local/cargo/git \
     cargo fetch --locked --target $TARGET_ARCH
 
#  if Cargo.toml has changed (e.g., new dependencies), but Cargo.lock hasn't been updated, the build fails
 RUN --mount=type=cache,target=/usr/local/cargo/registry \
     --mount=type=cache,target=/usr/local/cargo/git \
     cargo metadata --locked --all-features --format-version=1 > /dev/null 2>&1

#  build all crates in release mode
#  all members of the workspace
#  with all features.
# RUN --mount=type=cache,target=/usr/local/cargo/registry \
#      --mount=type=cache,target=/usr/local/cargo/git \
#      --mount=type=cache,target=/usr/src/app/target \
#      --network=none \
#      cargo build --release --frozen --workspace --target ${TARGET_ARCH} --all-features
    

# regex scratch
#RUN [[ "$name" =~ ^[a-zA-Z0-9_.-]+$ ]] || { echo "Invalid characters in: $name" >&2; exit 1; }

RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    cargo package --locked --all-features -vv
    # for name in $(jq -r '.[] | .name' ocl.json ); do echo "PUBLISHING: $name"; cargo publish -p "$name" --dry-run --target=x86_64-unknown-linux-musl; done

# --target=x86_64-unknown-linux-musl
# --no-verify
#
RUN ls -la /usr/src/app/output_crates/package/
RUN ls -la /usr/src/app/output_crates/package/*.crate

# --- Stage 2: layer for local extraction ---
FROM scratch AS export

COPY --from=builder /usr/src/app/output_crates/package/*.crate /exported
# there is no /bin/sh 
