#!/usr/bin/env bash

# ======================================================
# 📦 ADDON — ADIOS (Adaptive Deadline I/O Scheduler)
# by Masahito Suzuki (firelzrd)
# Repo: https://github.com/firelzrd/adios
# ======================================================
# Backport to android14-6.1: elevator_get() instead of elevator_find_get()
# (doesn't exist on 6.1), mq-deadline preserved as fallback default when
# ADIOS default is not selected (this tree has no SSG scheduler — see the
# patch header for how that was confirmed), and a NULL pointer fix in
# adios_completed_request() for UFS MCQ (rq->elv.priv[0] can be NULL for
# requests that never went through elevator insert).

ADIOS_PATCH="${LUMINAIRE_PATCH_DIR}/kernel/addons/adios/adios-android14-6.1-v3.2.0.patch"

log "📦 Applying ADIOS I/O scheduler patch..."
[ -f "$ADIOS_PATCH" ] || error "ADIOS: patch file not found at ${ADIOS_PATCH}!"

if patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$ADIOS_PATCH" > /dev/null 2>&1; then
    log "ADIOS: patch already applied, skipping."
elif patch -p1 --fuzz=3 --dry-run --forward -d "$KERNEL_SRC" < "$ADIOS_PATCH" > /dev/null 2>&1; then
    patch -p1 --fuzz=3 --forward -d "$KERNEL_SRC" < "$ADIOS_PATCH" \
        || error "ADIOS: patch apply failed!"
    log "ADIOS: patch applied ✅"
else
    error "ADIOS: patch does not apply cleanly — conflict or unsupported kernel source!"
fi

DEFCONFIG_FILE="${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"
if ! grep -q "^CONFIG_MQ_IOSCHED_ADIOS=y" "$DEFCONFIG_FILE"; then
    cat >> "$DEFCONFIG_FILE" << 'EOF'
# ADIOS I/O scheduler (Luminaire)
CONFIG_MQ_IOSCHED_ADIOS=y
CONFIG_MQ_IOSCHED_DEFAULT_ADIOS=y
EOF
    log "ADIOS: CONFIG_MQ_IOSCHED_ADIOS + DEFAULT_ADIOS enabled ✅"
fi

log "ADIOS I/O scheduler integrated ✅"
