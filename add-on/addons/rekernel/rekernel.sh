#!/usr/bin/env bash

# ======================================================
# 📦 ADDON — Re:Kernel (Binder/Signal Netlink server)
# ======================================================
# Repo: https://github.com/Sakion-Team/Re-Kernel
# Provides a Netlink server in the kernel that emits
# binder transaction and signal events for frozen procs,
# enabling tombstone apps (Thanox, HASS, Scene) to react
# to app kills and freezes in real time.

log "Integrating Re:Kernel..."

REKERNEL_PATCHER="${LUMINAIRE_PATCH_DIR}/kernel/addons/rekernel/inject.py"
REKERNEL_HEADER="${KERNEL_SRC}/drivers/android/rekernel.h"

python3 "$REKERNEL_PATCHER" "$KERNEL_SRC" \
    || error "Re:Kernel: injection failed!"

[ -f "$REKERNEL_HEADER" ] \
    || error "Re:Kernel: rekernel.h not created!"

log "Verifying Re:Kernel hook markers in source files..."
MARKER="Re:Kernel"
for _file in \
    "${KERNEL_SRC}/drivers/android/binder.c" \
    "${KERNEL_SRC}/drivers/android/binder_alloc.c" \
    "${KERNEL_SRC}/kernel/signal.c"; do
    grep -q "$MARKER" "$_file" \
        || error "Re:Kernel: hook marker missing in ${_file##*/} — injection silently failed!"
done
log "Re:Kernel hook markers verified ✅"

log "Re:Kernel integrated ✅"
