#!/usr/bin/env bash

# ======================================================
# 🔥 ADDON — BORE (Burst-Oriented Response Enhancer)
# CPU scheduler by Masahito Suzuki (firelzrd)
# Repo: https://github.com/firelzrd/bore-scheduler
# ======================================================
# KABI-safe backport to v5.3.0-equivalent for android14-6.1: all BORE
# fields live inside struct sched_entity's existing
# ANDROID_KABI_RESERVE(1-4) slots (ANDROID_KABI_USE/_ANDROID_KABI_REPLACE),
# so sizeof(struct sched_entity) and every field offset after it stays
# identical to a non-BORE GKI build — no vendor-module KABI break.

BORE_PATCH="${LUMINAIRE_PATCH_DIR}/kernel/addons/bore/bore-android14-6.1-v6.8.0.patch"

log "🔥 Applying BORE CPU scheduler patch..."
[ -f "$BORE_PATCH" ] || error "BORE: patch file not found at ${BORE_PATCH}!"

if patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$BORE_PATCH" > /dev/null 2>&1; then
    log "BORE: patch already applied, skipping."
elif patch -p1 --fuzz=3 --dry-run --forward -d "$KERNEL_SRC" < "$BORE_PATCH" > /dev/null 2>&1; then
    patch -p1 --fuzz=3 --forward -d "$KERNEL_SRC" < "$BORE_PATCH" \
        || error "BORE: patch apply failed!"
    log "BORE: patch applied ✅"
else
    error "BORE: patch does not apply cleanly — conflict or unsupported kernel source!"
fi

DEFCONFIG_FILE="${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"
if ! grep -q "^CONFIG_SCHED_BORE=y" "$DEFCONFIG_FILE"; then
    cat >> "$DEFCONFIG_FILE" << 'EOF'
# BORE CPU scheduler (Luminaire)
CONFIG_SCHED_BORE=y
EOF
    log "BORE: CONFIG_SCHED_BORE enabled ✅"
fi

log "BORE CPU scheduler integrated ✅"
