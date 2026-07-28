#!/usr/bin/env bash

# ======================================================
# 🪟 ADDON — NTSync
# Kernel-side NT synchronization primitive emulation
# Patch source: https://github.com/WildKernels/kernel_patches
# ======================================================
# Backports drivers/misc/ntsync.c (mainlined upstream, not yet present on
# this branch) plus the per-branch Kconfig/Makefile wiring. Mainly useful
# for Wine-based Windows compatibility layers (Winlator and similar) —
# NTSync offloads Windows NT wait/mutex/event primitives to the kernel
# instead of emulating them in userspace, which is significantly faster
# for games/apps that lean on them heavily.

NTSYNC_PATCHES_BASE="https://github.com/WildKernels/kernel_patches/raw/main/common/ntsync"

case "${KERNEL_VERSION}" in
    5.10) NTSYNC_COMPAT="ntsync_compat_android12-5.10.patch" ;;
    5.15) NTSYNC_COMPAT="ntsync_compat_android13-5.15.patch" ;;
    6.1)  NTSYNC_COMPAT="ntsync_compat_android14-6.1.patch"  ;;
    6.6)  NTSYNC_COMPAT="ntsync_compat_android15-6.6.patch"  ;;
    6.12) NTSYNC_COMPAT="ntsync_compat_android16-6.12.patch" ;;
    *)    error "NTSync: unsupported kernel version '${KERNEL_VERSION}'" ;;
esac

log "🪟 Applying NTSync patches (base + ${NTSYNC_COMPAT})..."
cd "${KERNEL_SRC}"

for NTSYNC_PATCH_FILE in "ntsync_base.patch" "${NTSYNC_COMPAT}"; do
    PATCH_CONTENT=$(curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 \
        "${NTSYNC_PATCHES_BASE}/${NTSYNC_PATCH_FILE}") \
        || error "NTSync: failed to download ${NTSYNC_PATCH_FILE}!"

    [ -n "$PATCH_CONTENT" ] || error "NTSync: downloaded patch ${NTSYNC_PATCH_FILE} is empty!"

    if echo "$PATCH_CONTENT" | patch -p1 --dry-run --reverse --no-backup-if-mismatch > /dev/null 2>&1; then
        log "NTSync: ${NTSYNC_PATCH_FILE} already applied, skipping."
    elif echo "$PATCH_CONTENT" | patch -p1 --dry-run --forward --no-backup-if-mismatch > /dev/null 2>&1; then
        echo "$PATCH_CONTENT" | patch -p1 --forward --no-backup-if-mismatch \
            || error "NTSync: ${NTSYNC_PATCH_FILE} apply failed!"
        log "NTSync: ${NTSYNC_PATCH_FILE} applied ✅"
    else
        error "NTSync: ${NTSYNC_PATCH_FILE} does not apply cleanly — conflict or unsupported kernel source!"
    fi
done

GKI_DEFCONFIG="${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"
if ! grep -q "^CONFIG_NTSYNC=y" "$GKI_DEFCONFIG"; then
    cat >> "$GKI_DEFCONFIG" << 'EOF'
# NTSync (Luminaire)
CONFIG_NTSYNC=y
EOF
    log "NTSync: CONFIG_NTSYNC enabled ✅"
fi

cd "${ROOT_DIR}"

log "NTSync driver integrated ✅"
