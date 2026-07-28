#!/usr/bin/env bash

# ======================================================
# 🗜️ ADDON — LZ4 1.10.0 + ZSTD 1.5.7 (ZRAM compression bump)
# ======================================================
# Patch source: https://github.com/mrcxlinux/kernel_patches (zram/)
# ======================================================
# Pure library version bump — no Kconfig involved, this just replaces the
# vendored lib/lz4 and lib/zstd source with newer upstream releases.
#
# The LZ4 patch contains 3 git-style rename hunks (fs/f2fs/lz4armv8/{
# lz4accel.c,lz4accel.h,lz4armv8.S} -> lib/lz4/lz4armv8/...) that assume an
# old f2fs-local copy already exists pre-patch. This GKI tree never carried
# that dir, so all 3 renames fail no matter what — confirmed by diffing
# lib/lz4/lz4_compress.c etc. against the patch's own assumed pre-image
# (byte-identical match), which rules out a source-mismatch explanation.
# These 3 files are NOT optional: the patch's new lib/lz4/lz4.h
# unconditionally `#include "lz4armv8/lz4accel.h"` (no arch guard at the
# include site — the guard lives inside lz4accel.h itself), so a missing
# lz4accel.h is a hard build break (fatal on every arch, not just arm64),
# confirmed by an actual CI failure before this was fixed. lz4armv8.S is
# also a binary git-diff (`patch` can't apply those at all). None of the
# 3 are hosted standalone upstream except lz4armv8.S, so lz4accel.c/.h are
# reconstructed here verbatim from their original upstream commit
# (pascua28/android_kernel_samsung_sm8250@0ac937e "Import arm64 V8 ASM lz4
# decompression acceleration") and pre-staged directly at their post-patch
# path, bypassing the patch tool's rename hunks entirely for all 3 files.
# lz4accel.h's #else branch makes it safe to include unconditionally on
# any arch (stubs out to a no-op when not arm64+NEON).
#
# We used to gate the whole apply behind one blanket `--dry-run --forward`
# check on the entire (40+ file) patch, which treated it as all-or-nothing:
# the (then-unhandled) rename hunks failing in the dry-run caused us to
# skip the *entire* patch, including ~13 other files (the actual 1.10.0
# algorithm source) that apply cleanly on their own. Fixed by applying
# directly — `patch` (unlike `git apply`) already continues past a failed
# hunk/file instead of aborting the rest — and verifying success via a
# real version marker in the patched source, not exit code alone (patch
# exits nonzero even when only the (now pre-staged, harmless) rename hunks
# fail).
#
# ZSTD is handled differently from LZ4 (see below): the mrcxlinux
# 002-zstd.patch targets ZSTD 1.5.7 but assumed a pre-image that no longer
# matches this tree's 1.4.10 source closely enough — confirmed by diffing
# both against upstream, several releases apart — so nearly every hunk
# rejected outright, not just a rename. A patch can't bridge that gap
# reliably, so instead of patching we fetch the full lib/zstd source tree
# (+ include/linux/zstd*.h) directly from torvalds/linux tag v6.15, which
# ships ZSTD 1.5.7 verbatim, and replace the vendored files wholesale.
# Verified compatible before wiring this up: v6.15's lib/zstd/Makefile
# keeps the same CONFIG_ZSTD_COMPRESS/DECOMPRESS/COMMON Kconfig symbols
# (only adds two new .o entries), and include/linux/zstd.h's v6.15 diff
# is purely additive — no existing wrapper function signature changed, so
# other in-tree callers (f2fs, zram, etc.) keep compiling untouched. One
# real incompatibility was found and is patched post-copy below: v6.15's
# common/mem.h includes the generic <linux/unaligned.h>, which doesn't
# exist yet in this 6.1 tree (only the arch-specific <asm/unaligned.h>
# does) — left as-is this is a fatal missing-header build break.
# (A separate intptr_t typedef removed from common/zstd_deps.h in v6.15
# was checked too: it's gated behind ZSTD_DEPS_NEED_STDINT, which nothing
# in this file set defines, so that branch is dead code either way —
# no fix needed there.)
#
# Non-fatal on failure (warn, not error): this is a compression-ratio/
# speed optimization, not a correctness-critical patch — a build without
# it just keeps whatever LZ4/ZSTD version this kernel branch already ships.

LZ4ZSTD_PATCH_BASE="https://raw.githubusercontent.com/mrcxlinux/kernel_patches/main/zram"
ZSTD_SRC_BASE="https://raw.githubusercontent.com/torvalds/linux/v6.15"
cd "${KERNEL_SRC}"

log "Downloading LZ4 patch..."
LZ4_PATCH=$(curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 "${LZ4ZSTD_PATCH_BASE}/001-lz4.patch") \
    || { warn "LZ4/ZSTD: failed to download 001-lz4.patch — skipping"; return 0; }
curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 -o /tmp/lz4armv8.S "${LZ4ZSTD_PATCH_BASE}/lz4armv8.S" \
    || { warn "LZ4/ZSTD: failed to download lz4armv8.S — skipping"; return 0; }

[ -n "$LZ4_PATCH" ] || { warn "LZ4/ZSTD: downloaded LZ4 patch is empty — skipping"; return 0; }

# Pre-stage all 3 arm64 accel files at their post-patch location (see
# header comment) so the LZ4 patch's own rename hunks — permanently
# unfixable in this tree — can't cost us files the patch's own lz4.h
# requires unconditionally to even compile.
mkdir -p lib/lz4/lz4armv8
cp /tmp/lz4armv8.S lib/lz4/lz4armv8/lz4armv8.S
cat > lib/lz4/lz4armv8/lz4accel.h << 'LZ4ACCEL_H_EOF'
#include <linux/types.h>
#include <asm/simd.h>

#define LZ4_FAST_MARGIN                (128)

#if defined(CONFIG_ARM64) && defined(CONFIG_KERNEL_MODE_NEON)
#include <asm/neon.h>
#include <asm/cputype.h>

asmlinkage int _lz4_decompress_asm(uint8_t **dst_ptr, uint8_t *dst_begin,
				   uint8_t *dst_end, const uint8_t **src_ptr,
				   const uint8_t *src_end, bool dip);

asmlinkage int _lz4_decompress_asm_noprfm(uint8_t **dst_ptr, uint8_t *dst_begin,
					  uint8_t *dst_end, const uint8_t **src_ptr,
					  const uint8_t *src_end, bool dip);

static inline int lz4_decompress_accel_enable(void)
{
	return	may_use_simd();
}

extern int (*lz4_decompress_asm_fn[])(uint8_t **dst_ptr, uint8_t *dst_begin,
	uint8_t *dst_end, const uint8_t **src_ptr,
	const uint8_t *src_end, bool dip);

static inline ssize_t lz4_decompress_asm(
	uint8_t **dst_ptr, uint8_t *dst_begin, uint8_t *dst_end,
	const uint8_t **src_ptr, const uint8_t *src_end, bool dip)
{
	int ret;

	kernel_neon_begin();
	ret = lz4_decompress_asm_fn[smp_processor_id()](dst_ptr, dst_begin,
						dst_end, src_ptr,
						src_end, dip);
	kernel_neon_end();
	return (ssize_t)ret;
}

#define __ARCH_HAS_LZ4_ACCELERATOR

#else

static inline int lz4_decompress_accel_enable(void)
{
	return	0;
}

static inline ssize_t lz4_decompress_asm(
	uint8_t **dst_ptr, uint8_t *dst_begin, uint8_t *dst_end,
	const uint8_t **src_ptr, const uint8_t *src_end, bool dip)
{
	return 0;
}
#endif
LZ4ACCEL_H_EOF
cat > lib/lz4/lz4armv8/lz4accel.c << 'LZ4ACCEL_C_EOF'
#include "lz4accel.h"
#include <asm/cputype.h>

#ifdef CONFIG_CFI_CLANG
static inline int
__cfi_lz4_decompress_asm(uint8_t **dst_ptr, uint8_t *dst_begin,
			 uint8_t *dst_end, const uint8_t **src_ptr,
			 const uint8_t *src_end, bool dip)
{
	return _lz4_decompress_asm(dst_ptr, dst_begin, dst_end,
				   src_ptr, src_end, dip);
}

static inline int
__cfi_lz4_decompress_asm_noprfm(uint8_t **dst_ptr, uint8_t *dst_begin,
				uint8_t *dst_end, const uint8_t **src_ptr,
				const uint8_t *src_end, bool dip)
{
	return _lz4_decompress_asm_noprfm(dst_ptr, dst_begin, dst_end,
					  src_ptr, src_end, dip);
}

#define _lz4_decompress_asm		__cfi_lz4_decompress_asm
#define _lz4_decompress_asm_noprfm	__cfi_lz4_decompress_asm_noprfm
#endif

int lz4_decompress_asm_select(uint8_t **dst_ptr, uint8_t *dst_begin,
			      uint8_t *dst_end, const uint8_t **src_ptr,
			      const uint8_t *src_end, bool dip) {
	const unsigned i = smp_processor_id();

	switch(read_cpuid_part_number()) {
	case ARM_CPU_PART_CORTEX_A53:
		lz4_decompress_asm_fn[i] = _lz4_decompress_asm_noprfm;
		return _lz4_decompress_asm_noprfm(dst_ptr, dst_begin, dst_end,
						  src_ptr, src_end, dip);
	}
	lz4_decompress_asm_fn[i] = _lz4_decompress_asm;
	return _lz4_decompress_asm(dst_ptr, dst_begin, dst_end,
				   src_ptr, src_end, dip);
}

int (*lz4_decompress_asm_fn[NR_CPUS])(uint8_t **dst_ptr, uint8_t *dst_begin,
	uint8_t *dst_end, const uint8_t **src_ptr,
	const uint8_t *src_end, bool dip)
__read_mostly = {
	[0 ... NR_CPUS-1]  = lz4_decompress_asm_select,
};
LZ4ACCEL_C_EOF

apply_lz4zstd_patch() {
    local name="$1" content="$2" marker_check="$3"

    if eval "$marker_check" 2>/dev/null; then
        log "LZ4/ZSTD: ${name} already applied, skipping."
        return 0
    fi

    # Files this patch touches, so we can cleanly revert them if the apply
    # doesn't actually land (see below) instead of leaving a half-patched
    # mix of old/new source behind.
    local touched_files
    touched_files=$(echo "$content" | grep -E '^\+\+\+ b/' | sed -E 's#^\+\+\+ b/##; s/\t.*//' | sort -u)

    # Apply directly instead of gating behind one blanket forward dry-run
    # on the whole multi-file patch — `patch` already applies hunk-by-hunk
    # and skips a failed hunk/file without aborting the rest, so a blanket
    # all-or-nothing pre-check only produces false negatives here.
    local patch_log
    patch_log=$(echo "$content" | patch -p1 --fuzz=3 --forward --no-backup-if-mismatch 2>&1)
    local rc=$?

    # Verify with real evidence (a version marker from the patched source)
    # rather than trusting exit code alone, since patch exits nonzero even
    # when only the (pre-staged, harmless) rename hunks failed.
    if eval "$marker_check" 2>/dev/null; then
        if [ "$rc" -eq 0 ]; then
            log "LZ4/ZSTD: ${name} applied cleanly ✅"
        else
            warn "LZ4/ZSTD: ${name} applied — core source updated, known ARM64 accel rename hunks skipped (expected, non-fatal) ⚠️"
        fi
    else
        warn "LZ4/ZSTD: ${name} core source did not update — reverting and skipping"
        echo "$touched_files" | while read -r f; do
            [ -z "$f" ] && continue
            if git ls-files --error-unmatch "$f" > /dev/null 2>&1; then
                git checkout -q -- "$f"
            else
                rm -f "$f"
            fi
            rm -f "${f}.rej"
        done
    fi
}

apply_lz4zstd_patch "001-lz4.patch (LZ4 1.10.0)" "$LZ4_PATCH" 'grep -q "LZ4_VERSION_MINOR 10" lib/lz4/lz4.h'

# Full lib/zstd source replacement (see header comment for why this isn't a
# patch apply). File list is the complete v6.15 lib/zstd tree plus its
# public include/linux/zstd*.h headers — anything not listed here is left
# untouched.
ZSTD_FILES=(
    lib/zstd/Makefile
    lib/zstd/decompress_sources.h
    lib/zstd/zstd_common_module.c
    lib/zstd/zstd_compress_module.c
    lib/zstd/zstd_decompress_module.c
    lib/zstd/common/allocations.h
    lib/zstd/common/bits.h
    lib/zstd/common/bitstream.h
    lib/zstd/common/compiler.h
    lib/zstd/common/cpu.h
    lib/zstd/common/debug.c
    lib/zstd/common/debug.h
    lib/zstd/common/entropy_common.c
    lib/zstd/common/error_private.c
    lib/zstd/common/error_private.h
    lib/zstd/common/fse.h
    lib/zstd/common/fse_decompress.c
    lib/zstd/common/huf.h
    lib/zstd/common/mem.h
    lib/zstd/common/portability_macros.h
    lib/zstd/common/zstd_common.c
    lib/zstd/common/zstd_deps.h
    lib/zstd/common/zstd_internal.h
    lib/zstd/compress/clevels.h
    lib/zstd/compress/fse_compress.c
    lib/zstd/compress/hist.c
    lib/zstd/compress/hist.h
    lib/zstd/compress/huf_compress.c
    lib/zstd/compress/zstd_compress.c
    lib/zstd/compress/zstd_compress_internal.h
    lib/zstd/compress/zstd_compress_literals.c
    lib/zstd/compress/zstd_compress_literals.h
    lib/zstd/compress/zstd_compress_sequences.c
    lib/zstd/compress/zstd_compress_sequences.h
    lib/zstd/compress/zstd_compress_superblock.c
    lib/zstd/compress/zstd_compress_superblock.h
    lib/zstd/compress/zstd_cwksp.h
    lib/zstd/compress/zstd_double_fast.c
    lib/zstd/compress/zstd_double_fast.h
    lib/zstd/compress/zstd_fast.c
    lib/zstd/compress/zstd_fast.h
    lib/zstd/compress/zstd_lazy.c
    lib/zstd/compress/zstd_lazy.h
    lib/zstd/compress/zstd_ldm.c
    lib/zstd/compress/zstd_ldm.h
    lib/zstd/compress/zstd_ldm_geartab.h
    lib/zstd/compress/zstd_opt.c
    lib/zstd/compress/zstd_opt.h
    lib/zstd/compress/zstd_preSplit.c
    lib/zstd/compress/zstd_preSplit.h
    lib/zstd/decompress/huf_decompress.c
    lib/zstd/decompress/zstd_ddict.c
    lib/zstd/decompress/zstd_ddict.h
    lib/zstd/decompress/zstd_decompress.c
    lib/zstd/decompress/zstd_decompress_block.c
    lib/zstd/decompress/zstd_decompress_block.h
    lib/zstd/decompress/zstd_decompress_internal.h
    include/linux/zstd.h
    include/linux/zstd_lib.h
    include/linux/zstd_errors.h
)

replace_zstd_source() {
    log "Downloading ZSTD 1.5.7 source tree from torvalds/linux v6.15..."

    if grep -q "ZSTD_VERSION_RELEASE  7" include/linux/zstd_lib.h 2>/dev/null; then
        log "LZ4/ZSTD: ZSTD 1.5.7 already applied, skipping."
        return 0
    fi

    # Stage the whole fetch in a scratch dir first and only touch the real
    # tree once every file is confirmed downloaded, so a mid-fetch network
    # failure can't leave a half-1.4.10/half-1.5.7 mix behind.
    local staging f
    staging=$(mktemp -d)
    for f in "${ZSTD_FILES[@]}"; do
        mkdir -p "${staging}/$(dirname "$f")"
        if ! curl -LSs --fail --retry 3 --retry-all-errors --connect-timeout 30 \
                -o "${staging}/${f}" "${ZSTD_SRC_BASE}/${f}"; then
            warn "LZ4/ZSTD: failed to download ${f} from v6.15 — skipping ZSTD bump, keeping existing 1.4.10 source"
            rm -rf "$staging"
            return 0
        fi
    done

    for f in "${ZSTD_FILES[@]}"; do
        mkdir -p "$(dirname "$f")"
        cp "${staging}/${f}" "$f"
    done
    rm -rf "$staging"

    # Compat fix: this 6.1 tree predates the generic <linux/unaligned.h>
    # wrapper header that v6.15's mem.h switched to — only the
    # arch-specific <asm/unaligned.h> exists here (see header comment).
    sed -i 's#include <linux/unaligned.h>#include <asm/unaligned.h>#' lib/zstd/common/mem.h

    if grep -q "ZSTD_VERSION_RELEASE  7" include/linux/zstd_lib.h; then
        log "LZ4/ZSTD: ZSTD bumped to 1.5.7 ✅"
    else
        warn "LZ4/ZSTD: ZSTD source replaced but version marker missing — check manually ⚠️"
    fi
}

replace_zstd_source

cd "${ROOT_DIR}"
log "LZ4/ZSTD bump done ✅"
