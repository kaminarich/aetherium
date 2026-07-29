#!/usr/bin/env bash

# ======================================================
# 📦 ADDON — LZ4KD (ZRAM compression optimization)
# ======================================================
# Source: https://github.com/SukiSU-Ultra/SukiSU_patch (other/zram/)
# ======================================================

LZ4KD_RAW_BASE="https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU_patch/main/other/zram"
# Target version otomatis baca environment KERNEL_VERSION dari workflow (default 6.1 kalau kosong)
TARGET_VER="${KERNEL_VERSION:-6.1}"

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
    curl -LSs -m 15 --fail --retry 3 --retry-all-errors \
        -o "$f" "${LZ4KD_RAW_BASE}/lz4k/${f}" \
        || error "LZ4KD: failed to download ${f}!"
done

log "LZ4KD source files staged ✅"

# Ambil patch sesuai dengan versi kernel-nya (misal: 5.10 atau 6.1)
LZ4KD_PATCH=$(curl -LSs -m 15 --fail --retry 3 --retry-all-errors \
    "${LZ4KD_RAW_BASE}/zram_patch/${TARGET_VER}/lz4kd.patch") \
    || error "LZ4KD: failed to download lz4kd.patch!"

[ -n "$LZ4KD_PATCH" ] || error "LZ4KD: downloaded patch is empty!"

# FIX OPLUS CONFLICT: SukiSU's patch contains an OPLUS-specific module blacklist hack in kernel/module.c
# which causes conflicts on standard GKI kernels. We slice it off dynamically!
LZ4KD_PATCH=$(echo "$LZ4KD_PATCH" | awk '/^diff -u a\/kernel\/module.c/{exit} {print}')

if echo "$LZ4KD_PATCH" | patch -p1 --batch --fuzz=3 --dry-run --reverse --no-backup-if-mismatch > /dev/null 2>&1; then
    log "LZ4KD: patch already applied, skipping."
elif echo "$LZ4KD_PATCH" | patch -p1 --batch --fuzz=3 --dry-run --forward --no-backup-if-mismatch > /dev/null 2>&1; then
    echo "$LZ4KD_PATCH" | patch -p1 --batch --fuzz=3 --forward --no-backup-if-mismatch \
        || error "LZ4KD: patch apply failed!"
    log "LZ4KD: patch applied ✅"
else
    error "LZ4KD: patch does not apply cleanly — conflict or unsupported kernel source!"
fi

# ------------------------------------------------------
# Force lz4kd to win over vendor init.rc comp_algorithm races
# ------------------------------------------------------
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

if echo "$ZRAM_FORCE_DEFAULT_PATCH" | patch -p1 --batch --fuzz=3 --dry-run --reverse --no-backup-if-mismatch > /dev/null 2>&1; then
    log "LZ4KD: zram force-default patch already applied, skipping."
elif echo "$ZRAM_FORCE_DEFAULT_PATCH" | patch -p1 --batch --fuzz=3 --dry-run --forward --no-backup-if-mismatch > /dev/null 2>&1; then
    echo "$ZRAM_FORCE_DEFAULT_PATCH" | patch -p1 --batch --fuzz=3 --forward --no-backup-if-mismatch \
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
