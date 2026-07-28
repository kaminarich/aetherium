#!/usr/bin/env bash

# ======================================================
# ⚙️ ADDON — Kcompressd-Unofficial
# Forked from Kcompressd (Qun-Wei Lin, MediaTek) by firelzrd
# Repo: https://github.com/firelzrd/kcompressd-unofficial
# ======================================================
# Port of kcompressd-unofficial 0.5 (closest upstream target: 6.12.44)
# to android14-6.1-lts. Offloads folio compression/swapout from kswapd
# to a dedicated per-node kthread, so kswapd's LRU scan isn't blocked
# on compression/IO.
#
# Per-node state (wait queue, kfifo, kthread) is kept in a private
# static array in mm/page_io.c instead of inside pg_data_t: unlike
# lru_gen_folio, pg_data_t is tracked in this kernel's frozen GKI ABI
# (android/abi_gki_aarch64.stg) and has no ANDROID_KABI_RESERVE slot
# to extend safely. Keeping the new state outside pg_data_t leaves its
# layout — and vendor .ko compatibility — untouched.
#
# This kernel has no CONFIG_ZSWAP (confirmed absent, device uses ZRAM
# only), so the upstream zswap branches are dropped; eligibility is
# decided purely by SWP_SYNCHRONOUS_IO, which zram sets.
#
# On by default: vm.kcompressd defaults to 24 (FIFO depth) at compile
# time, same as upstream — no sysctl write needed after boot.
# Disable at runtime with: sysctl -w vm.kcompressd=0
#
# Compatible with the le9uo addon: both patch kernel/sysctl.c and
# mm/vmscan.c at non-overlapping anchors, verified to apply cleanly
# together in either order.

KCOMPRESSD_PATCH="${LUMINAIRE_PATCH_DIR}/kernel/addons/kcompressd/kcompressd-android14-6.1-v0.5.patch"

log "⚙️ Applying Kcompressd-Unofficial patch..."
[ -f "$KCOMPRESSD_PATCH" ] || error "kcompressd: patch file not found at ${KCOMPRESSD_PATCH}!"

if patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$KCOMPRESSD_PATCH" > /dev/null 2>&1; then
    log "kcompressd: patch already applied, skipping."
elif patch -p1 --fuzz=3 --dry-run --forward -d "$KERNEL_SRC" < "$KCOMPRESSD_PATCH" > /dev/null 2>&1; then
    patch -p1 --fuzz=3 --forward -d "$KERNEL_SRC" < "$KCOMPRESSD_PATCH" \
        || error "kcompressd: patch apply failed!"
    log "kcompressd: patch applied ✅"
else
    error "kcompressd: patch does not apply cleanly — conflict or unsupported kernel source!"
fi

log "Kcompressd-Unofficial integrated ✅"
