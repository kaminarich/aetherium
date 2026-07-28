#!/usr/bin/env bash

# Compiles kasumi_lkm.ko as an out-of-tree module against the kernel tree
# run_build() just finished producing (needs its Module.symvers).

[ -n "${KASUMI_SRC_DIR:-}" ] || error "Kasumi: KASUMI_SRC_DIR not set — kasumi.sh addon may not have run correctly!"

log "🥷 Building Kasumi LKM (kasumi_lkm.ko)..."

KASUMI_MAKE_ARGS=(
    -C "$KERNEL_SRC"
    O="$OUT_DIR"
    ARCH="$ARCH"
    CROSS_COMPILE="$TOOL_CROSS_COMPILE"
    LLVM=1
    LLVM_IAS=1
    M="${KASUMI_SRC_DIR}/src"
    CC="${TOOL_CCACHE_WRAPPERS}/clang"
)

make "${KASUMI_MAKE_ARGS[@]}" modules \
    || error "Kasumi: module build failed!"

KASUMI_KO=$(find "${KASUMI_SRC_DIR}/src" -name "*.ko" | head -1)
[ -n "$KASUMI_KO" ] || error "Kasumi: build succeeded but no .ko file found under ${KASUMI_SRC_DIR}/src!"

export KASUMI_KO
log "Kasumi LKM built: $(basename "$KASUMI_KO") ✅"
