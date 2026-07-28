#!/usr/bin/env bash

# ======================================================
# 📦 ADDON — BBG (Baseband Guard LSM)
# ======================================================
# Repo: https://github.com/vc-teahouse/Baseband-guard

log "Setting up Baseband Guard (BBG)..."
cd "${KERNEL_SRC}"
BBG_SETUP=$(curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 \
    "https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh") \
    || error "BBG: failed to download setup.sh!"
[ -n "$BBG_SETUP" ] || error "BBG: setup.sh is empty!"
echo "$BBG_SETUP" | grep -q "^#!" || error "BBG: setup.sh looks invalid (no shebang)!"
echo "$BBG_SETUP" | bash || error "BBG: setup.sh failed!"
[ -L "${KERNEL_SRC}/security/baseband-guard" ] \
    || error "BBG: inject failed — security/baseband-guard symlink not found!"

PATCHER="${LUMINAIRE_PATCH_DIR}/kernel/addons/bbg/kconfig_inject.py"
python3 "$PATCHER" "${KERNEL_SRC}/security/Kconfig" \
    || error "BBG: Kconfig inject failed!"

cd "${ROOT_DIR}"

DEFCONFIG_FILE="${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"

log "Enabling CONFIG_BBG..."
if ! grep -q "^CONFIG_BBG=y" "$DEFCONFIG_FILE"; then
    echo "CONFIG_BBG=y" >> "$DEFCONFIG_FILE"
fi

export BBG_ENABLED=true

log "BBG setup complete ✅ (CONFIG_LSM will be patched after defconfig)"
