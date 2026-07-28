#!/usr/bin/env bash

# ======================================================
# 📦 ADDON — LZ4KD (ZRAM compression optimization)
# ======================================================
# Source: https://github.com/SukiSU-Ultra/SukiSU_patch (other/zram/)
# ======================================================
# Adds the lz4k/lz4kd compressor backends for zram (kernel-delta-aware
# variants of LZ4) plus the Kconfig/Makefile/zcomp.c wiring to register
# them. Version-keyed by upstream per kernel branch — this repo only
# targets android14-6.1-lts, so only that one path is used below; add a
# case statement here if a second kernel version is ever supported.

LZ4KD_RAW_BASE="https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU_patch/main/other/zram"

cd "${KERNEL_SRC}"

log "Downloading LZ4KD source files..."

LZ4KD_FILES=(
    "include/linux/lz4k.h"
    "include/linux/lz4kd.h"
    "lib/lz4k/Makefile"
    "lib/lz4k/lz4k_decode.c"
    "lib/lz4k/lz4k_encode.c"
    "lib/lz4k/lz4k_encode_private.h"
    "lib/lz4k/lz4k_private.h"
    "lib/lz4kd/Makefile"
    "lib/lz4kd/lz4kd_decode.c"
    "lib/lz4kd/lz4kd_decode_delta.c"
    "lib/lz4kd/lz4kd_encode.c"
    "lib/lz4kd/lz4kd_encode_delta.c"
    "lib/lz4kd/lz4kd_encode_private.h"
    "lib/lz4kd/lz4kd_private.h"
    "crypto/lz4k.c"
    "crypto/lz4kd.c"
)

for f in "${LZ4KD_FILES[@]}"; do
    mkdir -p "$(dirname "$f")"
    curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 \
        -o "$f" "${LZ4KD_RAW_BASE}/lz4k/${f}" \
        || error "LZ4KD: failed to download ${f}!"
done

log "LZ4KD source files staged ✅"

LZ4KD_PATCH=$(curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 \
    "${LZ4KD_RAW_BASE}/zram_patch/6.1/lz4kd.patch") \
    || error "LZ4KD: failed to download lz4kd.patch!"

[ -n "$LZ4KD_PATCH" ] || error "LZ4KD: downloaded patch is empty!"

if echo "$LZ4KD_PATCH" | patch -p1 --fuzz=3 --dry-run --reverse --no-backup-if-mismatch > /dev/null 2>&1; then
    log "LZ4KD: patch already applied, skipping."
elif echo "$LZ4KD_PATCH" | patch -p1 --fuzz=3 --dry-run --forward --no-backup-if-mismatch > /dev/null 2>&1; then
    echo "$LZ4KD_PATCH" | patch -p1 --fuzz=3 --forward --no-backup-if-mismatch \
        || error "LZ4KD: patch apply failed!"
    log "LZ4KD: patch applied ✅"
else
    error "LZ4KD: patch does not apply cleanly — conflict or unsupported kernel source!"
fi

# ------------------------------------------------------
# Force lz4kd to win over vendor init.rc comp_algorithm races
# ------------------------------------------------------
# Confirmed on-device: CONFIG_ZRAM_DEF_COMP="lz4kd" compiles in fine, but
# /sys/block/zram0/comp_algorithm still came up [lz4] after boot. Root
# cause: some OEM vendor init.rc scripts `write comp_algorithm <algo>`
# during early boot — legal, since comp_algorithm_store() only refuses
# writes *after* init_done(zram) is true (drivers/block/zram/zram_drv.c).
# That write silently wins over our Kconfig default because it lands
# after zram_add() sets it but before disksize_store() locks it in for
# good — no boot-time retry loop can fix this after the fact (once
# init_done, comp_algorithm_store() flatly returns -EBUSY), so the only
# correct place to win the race is one line, inside disksize_store()
# itself, right before zcomp_create() — the true last point before the
# choice becomes permanent. Gated on CONFIG_ZRAM_DEF_COMP_LZ4KD, which is
# already auto-set by the defconfig line below, so it stays inert if the
# default is ever changed away from lz4kd.
ZRAM_FORCE_DEFAULT_PATCH=$(cat << 'PATCHEOF'
--- a/drivers/block/zram/zram_drv.c
+++ b/drivers/block/zram/zram_drv.c
@@ -1768,6 +1768,19 @@ static ssize_t disksize_store(struct device *dev,
 		goto out_unlock;
 	}
 
+#ifdef CONFIG_ZRAM_DEF_COMP_LZ4KD
+	/*
+	 * Some vendor init.rc scripts write their own preferred algorithm to
+	 * comp_algorithm during early boot -- still legal at this point,
+	 * since it happens before init_done(zram) is set. Whatever string is
+	 * in zram->compressor right as zcomp_create() below runs becomes
+	 * permanent for this device's lifetime, so re-assert our
+	 * compile-time default one last time, here, to win regardless of
+	 * how many earlier writes raced it.
+	 */
+	strscpy(zram->compressor, default_compressor, sizeof(zram->compressor));
+#endif
+
 	comp = zcomp_create(zram->compressor);
 	if (IS_ERR(comp)) {
 		pr_err("Cannot initialise %s compressing backend\n",
PATCHEOF
)

if echo "$ZRAM_FORCE_DEFAULT_PATCH" | patch -p1 --fuzz=3 --dry-run --reverse --no-backup-if-mismatch > /dev/null 2>&1; then
    log "LZ4KD: zram force-default patch already applied, skipping."
elif echo "$ZRAM_FORCE_DEFAULT_PATCH" | patch -p1 --fuzz=3 --dry-run --forward --no-backup-if-mismatch > /dev/null 2>&1; then
    echo "$ZRAM_FORCE_DEFAULT_PATCH" | patch -p1 --fuzz=3 --forward --no-backup-if-mismatch \
        || error "LZ4KD: zram force-default patch apply failed!"
    log "LZ4KD: zram force-default patch applied ✅"
else
    error "LZ4KD: zram force-default patch does not apply cleanly — conflict or unsupported kernel source!"
fi

GKI_DEFCONFIG="${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"

if ! grep -q "^CONFIG_CRYPTO_LZ4KD=y" "$GKI_DEFCONFIG"; then
    cat >> "$GKI_DEFCONFIG" << 'CONFIGS'
# LZ4KD (Luminaire)
CONFIG_CRYPTO_LZ4HC=y
CONFIG_CRYPTO_LZ4K=y
CONFIG_CRYPTO_LZ4KD=y
CONFIGS
    log "LZ4KD: configs enabled ✅"
fi

# Sets lz4kd as the ZRAM compressor's compile-time default. This has to be a
# separate, independently-guarded block from the CONFIG_CRYPTO_LZ4KD=y one
# above: that block only appends on a fresh defconfig (its guard is
# CONFIG_CRYPTO_LZ4KD not yet present), so on a rebuild where the crypto
# lines already landed, the def-comp line would silently never get added if
# it lived in the same block.
if ! grep -q '^CONFIG_ZRAM_DEF_COMP="lz4kd"' "$GKI_DEFCONFIG"; then
    cat >> "$GKI_DEFCONFIG" << 'CONFIGS'
# LZ4KD as ZRAM default compressor (Luminaire)
CONFIG_ZRAM_DEF_COMP="lz4kd"
CONFIGS
    log "LZ4KD: set as ZRAM default compressor ✅"
fi

export LZ4KD_ENABLED=true

cd "${ROOT_DIR}"

log "LZ4KD ZRAM optimization integrated ✅"
