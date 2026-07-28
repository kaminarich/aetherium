#!/usr/bin/env bash

# ======================================================
# 📦 ADDON — Droidspaces (LXC container runtime)
# ======================================================
# Requires: 001_GKI-below-6_12-fix_sysvipc_kabi_6_7_8.patch
# Docs: https://github.com/ravindu644/Droidspaces-OSS

log "Enabling Droidspaces support..."

KABI_PATCH="`$LUMINAIRE_PATCH_DIR/kernel/patches/001_GKI-below-6_12-fix_sysvipc_kabi_6_7_8.patch"
if [ ! -f "$KABI_PATCH" ]; then
    warn "Droidspaces: KaBI patch not found at ${KABI_PATCH} — SYSVIPC may cause KaBI violations on some devices"
elif patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$KABI_PATCH" > /dev/null 2>&1; then
    log "Droidspaces: KaBI patch already applied ✅"
elif patch -p1 --fuzz=3 --dry-run --forward -d "$KERNEL_SRC" < "$KABI_PATCH" > /dev/null 2>&1; then
    patch -p1 --fuzz=3 -d "$KERNEL_SRC" < "$KABI_PATCH" \
        || error "Droidspaces: KaBI patch failed — aborting to prevent KaBI violations!"
    log "Droidspaces: KaBI patch applied ✅"
else
    warn "Droidspaces: KaBI patch does not apply cleanly — skipping, KaBI violations possible"
fi
if ! grep -q "^CONFIG_SYSVIPC=y" "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig"; then
    cat >> "${KERNEL_SRC}/arch/arm64/configs/gki_defconfig" << 'CONFIGS'
# Droidspaces — Mandatory
CONFIG_SYSVIPC=y
CONFIG_PID_NS=y
CONFIG_IPC_NS=y
CONFIG_UTS_NS=y
CONFIG_DEVTMPFS=y
CONFIG_CGROUP_DEVICE=y

# Droidspaces — Networking (NAT mode)
CONFIG_NET_NS=y
CONFIG_NETFILTER_XT_TARGET_LOG=y
CONFIG_NETFILTER_XT_MATCH_RECENT=y

# Droidspaces — Binfmt
CONFIG_BINFMT_ELF=y
CONFIG_BINFMT_SCRIPT=y
CONFIGS
fi
log "Droidspaces configs enabled ✅"
