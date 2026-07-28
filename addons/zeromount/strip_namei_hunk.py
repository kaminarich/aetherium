#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
#
# strip_namei_hunk.py — strip the fs/namei.c hunks from ZeroMount patch
#
# The ZeroMount patch's fs/namei.c section is diffed against a SuSFS-
# patched baseline — its first hunk's unchanged context includes
# `#ifdef CONFIG_KSU_SUSFS_UNICODE_FILTER` / `extern bool
# susfs_check_unicode_bypass(...)`, which only exists once SuSFS has
# already been patched in. Applying it to a non-SuSFS tree means that
# context can't match, and --fuzz=3 will still force a match rather than
# fail outright — landing the later hunks (the generic_permission()/
# inode_permission() permission-check injections) outside the actual
# function bodies, producing "undeclared identifier 'inode'/'mask'"
# compile errors. Confirmed via a VANILLA build failure (fs/namei.c:833)
# while the same patch applied cleanly on all three SuSFS-patched
# variants in the same run — VANILLA (and any non-SuSFS variant) is no
# longer a supported combo for this addon at all (see zeromount.sh), but
# the failure mode that led here is still the reason this strip exists.
#
# inject_namei.py handles fs/namei.c via anchor-based injection instead
# (anchors are baseline-agnostic real function bodies), so the patch
# hunks are not needed. This mirrors strip_readdir_hunk.py, which strips
# the same-root-cause-affected fs/readdir.c hunk.
#
# This script strips the namei.c diff section from the patch file
# in-place before it is applied, guaranteeing zero hunk failures and
# zero silent mis-application.

import sys


def strip_namei_hunk(path):
    with open(path, "r", errors="replace") as f:
        lines = f.readlines()

    out = []
    skip = False

    for i, line in enumerate(lines):
        # Detect start of namei.c diff section
        if line.startswith("--- a/fs/namei.c"):
            skip = True

        # Detect start of next diff section after namei.c — stop skipping
        if skip and i > 0 and line.startswith("--- a/") and "namei.c" not in line:
            skip = False

        if not skip:
            out.append(line)

    if len(out) == len(lines):
        print(
            "[warn] strip_namei_hunk: namei.c section not found in patch — "
            "patch may have changed upstream; proceeding without strip"
        )
        sys.exit(0)

    with open(path, "w") as f:
        f.writelines(out)

    removed = len(lines) - len(out)
    print(f"[info] strip_namei_hunk: stripped {removed} lines (namei.c hunk) from patch ✅")
    sys.exit(0)


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path/to/patch>", file=sys.stderr)
        sys.exit(1)
    strip_namei_hunk(sys.argv[1])


if __name__ == "__main__":
    main()
