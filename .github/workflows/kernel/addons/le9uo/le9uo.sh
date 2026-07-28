#!/usr/bin/env bash

# ======================================================
# 🛡️ ADDON — le9uo (Working Set Protection)
# Forked from hakavlad/le9-patch, maintained by firelzrd
# Repo: https://github.com/firelzrd/le9uo
# ======================================================
# Port of le9uo 1.15 (upstream target: 6.15) to android14-6.1-lts.
# Upstream 1.15 no longer touches kernel/sysctl.c (vm sysctls moved to
# mm/util.c in later upstream) and uses MIN/MAX_SWAPPINESS +
# for_each_evictable_type(), neither of which exist on 6.1. This patch
# reimplements the same logic (sysctl_workingset_protection/
# anon_min_ratio/clean_low_ratio/clean_min_ratio, hard+soft protection
# in shrink_folio_list/get_scan_count, and the MGLRU-path override in
# get_type_to_scan/isolate_folios/shrink_one) directly against this
# kernel's actual 6.1 vmscan.c, including its extra get_type_to_scan()
# tier_idx out-param and its prepare_scan_count()/mem_cgroup_below_min()
# signatures, which differ from upstream. kernel/sysctl.c is patched
# directly (still monolithic on 6.1, same spot as vm.swappiness).
#
# Disabled at compile-time is NOT the default here: sysctl_workingset_protection
# is gated on CONFIG_WORKINGSET_PROTECTION_ENABLED, forced =y below, so
# protection is active from the kernel's first reclaim cycle — no
# `sysctl -w vm.workingset_protection=1` needed after boot.
#
# Known interaction: trace_android_vh_isolate_folio_type() in
# isolate_folios() runs AFTER this patch's type selection and can be
# overridden by a vendor module — not patched here, left as upstream
# GKI vendor-hook behavior. Verify on-device if a MTK vendor blob
# already overrides anon/file balance.

LE9UO_PATCH="${LUMINAIRE_PATCH_DIR}/kernel/addons/le9uo/le9uo-android14-6.1-v1.15.patch"

log "🛡️ Applying le9uo working set protection patch..."
[ -f "$LE9UO_PATCH" ] || error "le9uo: patch file not found at ${LE9UO_PATCH}!"

if patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$LE9UO_PATCH" > /dev/null 2>&1; then
    log "le9uo: patch already applied, skipping."
elif patch -p1 --fuzz=3 --dry-run --forward -d "$KERNEL_SRC" < "$LE9UO_PATCH" > /dev/null 2>&1; then
    patch -p1 --fuzz=3 --forward -d "$KERNEL_SRC" < "$LE9UO_PATCH" \
        || error "le9uo: patch apply failed!"
    log "le9uo: patch applied ✅"
else
    error "le9uo: patch does not apply cleanly — conflict or unsupported kernel source!"
fi

# Force the enabled-by-default Kconfig + the ratio defaults into the
# defconfig explicitly, in case anything in the pipeline (savedefconfig,
# olddefconfig against a different base) would otherwise drop or silently
# reset a bare `default` from Kconfig. This guarantees the sysctl.d-less
# on-device behavior: vm.workingset_protection=1 already active at first
# boot with no init script, no vendor init.rc write, no user step at all.
GKI_DEFCONFIG="${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"
if ! grep -q "^CONFIG_WORKINGSET_PROTECTION_ENABLED=y" "$GKI_DEFCONFIG"; then
    cat >> "$GKI_DEFCONFIG" << 'CONFIGS'
# le9uo Working Set Protection — active from boot (Luminaire)
CONFIG_WORKINGSET_PROTECTION_ENABLED=y
CONFIG_ANON_MIN_RATIO=15
CONFIG_CLEAN_LOW_RATIO=0
CONFIG_CLEAN_MIN_RATIO=15
CONFIGS
    log "le9uo: defconfig forced (protection active from first boot) ✅"
fi

log "le9uo Working Set Protection integrated ✅"
