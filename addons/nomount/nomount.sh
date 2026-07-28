#!/usr/bin/env bash

# ======================================================
# 📦 ADDON — NoMount (VFS path injection framework)
# ======================================================
# Repo: https://github.com/maxsteeel/nomount
# Status: Beta

NOMOUNT_REPO="https://github.com/maxsteeel/nomount"
NOMOUNT_DIR="/tmp/nomount_src"
NOMOUNT_PATCH_NAME="nomount_${KERNEL_VERSION}_kernel_integration.patch"

log "Integrating NoMount..."

[ -d "$NOMOUNT_DIR" ] && rm -rf "$NOMOUNT_DIR"
git config --global http.connectTimeout 30
git config --global http.lowSpeedLimit 1000
git config --global http.lowSpeedTime 30
retry 3 run_quiet git clone -q --depth=1 "$NOMOUNT_REPO" "$NOMOUNT_DIR" \
    || { warn "NoMount clone failed — skipping"; return 0; }

NOMOUNT_PATCH="${NOMOUNT_DIR}/kernel/patches/${NOMOUNT_PATCH_NAME}"
if [ ! -f "$NOMOUNT_PATCH" ]; then
    warn "NoMount patch not found for kernel ${KERNEL_VERSION} — skipping"
    rm -rf "$NOMOUNT_DIR"
    return 0
fi

log "Copying NoMount source files..."
cp "${NOMOUNT_DIR}/kernel/src/nomount.c" "${KERNEL_SRC}/fs/nomount.c"
cp "${NOMOUNT_DIR}/kernel/src/nomount.h" "${KERNEL_SRC}/fs/nomount.h"
log "NoMount source files copied ✅"

log "Applying NoMount kernel patch..."
if patch -p1 --fuzz=10 --dry-run --reverse -d "$KERNEL_SRC" < "$NOMOUNT_PATCH" > /dev/null 2>&1; then
    log "NoMount patch already applied, skipping."
else
    patch -p1 --fuzz=10 --forward -d "$KERNEL_SRC" < "$NOMOUNT_PATCH" \
        && log "NoMount patch applied ✅" \
        || warn "NoMount patch: some hunks failed — continuing"
    find "$KERNEL_SRC" -name "*.rej" -delete 2>/dev/null || true
fi

# Guard: verify NoMount was actually wired in before enabling the config.
# Without this, hunk failures above only warn — the build would otherwise
# report success with CONFIG_NOMOUNT=y while the feature is dead code.
# We check that some caller in fs/ (other than the copied source itself)
# now #includes nomount.h — that's the minimum signal the patch actually
# hooked NoMount into the VFS rather than just dropping unused files.
if ! grep -rlF '#include "nomount.h"' "${KERNEL_SRC}/fs/" 2>/dev/null \
        | grep -qv '/nomount\.c$'; then
    warn "NoMount: no caller includes nomount.h after patch — integration may have failed entirely"
    warn "NoMount integration incomplete — kernel will build without NoMount"
    rm -rf "$NOMOUNT_DIR"
    return 0
fi

rm -rf "$NOMOUNT_DIR"

log "Enabling NoMount config..."
if ! grep -q "^CONFIG_NOMOUNT=y" "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"; then
    cat >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig" << 'CONFIGS'
CONFIG_NOMOUNT=y
CONFIGS
fi

log "NoMount integrated ✅"
