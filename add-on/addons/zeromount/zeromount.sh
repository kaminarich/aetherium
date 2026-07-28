#!/usr/bin/env bash

# ======================================================
# 📦 ADDON — ZeroMount (VFS path redirection engine)
# ======================================================
# Repo: https://github.com/Enginex0/zeromount
# Patch source: https://github.com/Enginex0/Super-Builders
# Note: self-contained patch (creates fs/zeromount.c,
#       include/linux/zeromount.h, Kconfig + Makefile wiring).
#       readdir.c and namei.c hunks are stripped before apply — both are
#       diffed against a SuSFS-patched baseline and are handled exclusively
#       by inject_readdir.py / inject_namei.py instead.
#
# Requires SuSFS — build.sh's addon conflict matrix (run_addons()) rejects
# this addon outright when SUSFS_ENABLED isn't true, on any variant
# including VANILLA (which can never have SuSFS). Design decision, not a
# hard limitation of every script here: inject_namei.py/inject_readdir.py
# are baseline-agnostic and would work on a non-SuSFS tree too, but
# fix_taskmmu.py's scope fix only handles the SuSFS-patched pattern (its
# non-SuSFS case was removed once this addon stopped supporting non-SuSFS
# trees), so this is a hard requirement in practice regardless.

ZEROMOUNT_PATCH_URL="https://raw.githubusercontent.com/Enginex0/Super-Builders/main/android14-6.1/ReSukiSU/patches/60_zeromount-android14-6.1.patch"
ZEROMOUNT_PATCH="/tmp/60_zeromount-android14-6.1.patch"
PATCHER_DIR="${LUMINAIRE_PATCH_DIR}/kernel/addons/zeromount"

log "Downloading ZeroMount kernel patch..."
retry 3 run_quiet curl -fSL "$ZEROMOUNT_PATCH_URL" -o "$ZEROMOUNT_PATCH" \
    || { warn "ZeroMount patch download failed — skipping"; return 0; }

log "Stripping readdir.c hunk from patch..."
python3 "${PATCHER_DIR}/strip_readdir_hunk.py" "$ZEROMOUNT_PATCH" \
    || { warn "ZeroMount: strip_readdir_hunk failed — skipping"; rm -f "$ZEROMOUNT_PATCH"; return 0; }

log "Stripping namei.c hunks from patch..."
python3 "${PATCHER_DIR}/strip_namei_hunk.py" "$ZEROMOUNT_PATCH" \
    || { warn "ZeroMount: strip_namei_hunk failed — skipping"; rm -f "$ZEROMOUNT_PATCH"; return 0; }

log "Applying ZeroMount kernel patch..."
if patch -p1 --fuzz=3 --dry-run --reverse -d "$KERNEL_SRC" < "$ZEROMOUNT_PATCH" > /dev/null 2>&1; then
    log "ZeroMount patch already applied, skipping."
else
    patch -p1 --fuzz=3 --forward -d "$KERNEL_SRC" < "$ZEROMOUNT_PATCH" > /tmp/zm_patch.log 2>&1 \
        || error "ZeroMount patch failed — check /tmp/zm_patch.log for details"
    log "ZeroMount patch applied ✅"
    rm -f /tmp/zm_patch.log
fi

rm -f "$ZEROMOUNT_PATCH"

log "Injecting ZeroMount hooks into namei.c (include, getname hook, permission checks)..."
python3 "${PATCHER_DIR}/inject_namei.py" "${KERNEL_SRC}/fs/namei.c" \
    || error "ZeroMount: namei.c injection failed!"
log "namei.c injected ✅"

log "Fixing task_mmu.c scope issue (zeromount call outside inode scope)..."
python3 "${PATCHER_DIR}/fix_taskmmu.py" "${KERNEL_SRC}/fs/proc/task_mmu.c" \
    || error "ZeroMount: task_mmu.c fix failed!"
log "task_mmu.c fixed ✅"

log "Injecting ZeroMount hooks into readdir.c (directory listing support)..."
python3 "${PATCHER_DIR}/inject_readdir.py" "${KERNEL_SRC}/fs/readdir.c" \
    || error "ZeroMount: readdir.c injection failed!"
log "readdir.c injected ✅"

log "ZeroMount integrated ✅"
