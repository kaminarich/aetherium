#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
#
# inject_readdir.py — inject ZeroMount hooks into fs/readdir.c
#
# Handles readdir.c injection for every ZeroMount build (RESUKISU, SUKISU,
# KSUNEXT — ZeroMount requires SuSFS, so VANILLA is never a valid combo,
# see zeromount.sh), replacing the readdir.c hunks from the ZeroMount
# patch which require SuSFS context to apply cleanly. The ZeroMount patch
# is pre-stripped of its readdir.c hunk (via strip_readdir_hunk.py) before
# being applied, so this worker is always the sole authority for
# readdir.c injection.

import sys

IDEMPOTENCY_MARKER = "#ifdef CONFIG_ZEROMOUNT"

INCLUDE_ANCHOR = "#include <asm/unaligned.h>"
INCLUDE_INJECT = (
    "\n"
    "#ifdef CONFIG_ZEROMOUNT\n"
    "#include <linux/zeromount.h>\n"
    "#endif"
)

# Anchor: the getdents (non-compat) fdget_pos block
FDGET_ANCHOR = "f = fdget_pos(fd);"
FDGET_NEXT   = "if (!f.file)"

FDGET_INJECT = (
    "#ifdef CONFIG_ZEROMOUNT\n"
    "\tint initial_count = count;\n"
    "#endif\n"
    "\n"
)

# Anchor: iterate_dir call inside getdents
ITERATE_ANCHOR = "error = iterate_dir(f.file, &buf.ctx);"
ITERATE_NEXT   = "if (error >= 0)"

ITERATE_INJECT_BEFORE = (
    "#ifdef CONFIG_ZEROMOUNT\n"
    "\tif (f.file->f_pos >= ZEROMOUNT_MAGIC_POS) {\n"
    "\t\terror = 0;\n"
    "\t\tgoto skip_real_iterate;\n"
    "\t}\n"
    "#endif\n"
    "\n"
)

ITERATE_INJECT_AFTER = (
    "\n"
    "#ifdef CONFIG_ZEROMOUNT\n"
    "skip_real_iterate:\n"
    "\tif (error >= 0 && !signal_pending(current)) {\n"
    "\t\tzeromount_inject_dents(f.file, (void __user **)&dirent, &count, &f.file->f_pos);\n"
    "\t\tif (count != initial_count)\n"
    "\t\t\terror = initial_count - count;\n"
    "\t\tgoto zm_out;\n"
    "\t}\n"
    "#endif\n"
)

ZM_OUT_ANCHOR  = "fdput_pos(f);"
ZM_OUT_INJECT  = "zm_out:\n"


def find_getdents_non_compat(lines):
    """
    Return the line index of SYSCALL_DEFINE3(getdents, ...) that is NOT
    inside #ifdef CONFIG_COMPAT. We want the non-compat variant only.
    """
    in_compat = False
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped == "#ifdef CONFIG_COMPAT":
            in_compat = True
        if stripped == "#endif" and in_compat:
            in_compat = False
        if not in_compat and "SYSCALL_DEFINE3(getdents," in line:
            return i
    return None


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path/to/fs/readdir.c>", file=sys.stderr)
        sys.exit(1)

    path = sys.argv[1]

    with open(path, "r") as f:
        content = f.read()

    # Idempotency check
    if IDEMPOTENCY_MARKER in content:
        print("[info] fix_readdir: ZeroMount already injected — skipping ✅")
        sys.exit(0)

    lines = content.splitlines(keepends=True)

    # ------------------------------------------------------------------ #
    # 1. Inject #include <linux/zeromount.h>
    # ------------------------------------------------------------------ #
    include_idx = None
    for i, line in enumerate(lines):
        if line.strip() == INCLUDE_ANCHOR:
            include_idx = i
            break

    if include_idx is None:
        print(
            f"[error] fix_readdir: anchor '{INCLUDE_ANCHOR}' not found — "
            "upstream readdir.c may have changed!",
            file=sys.stderr,
        )
        sys.exit(1)

    lines.insert(include_idx + 1, INCLUDE_INJECT + "\n")

    # ------------------------------------------------------------------ #
    # 2. Find SYSCALL_DEFINE3(getdents) — non-compat variant
    # ------------------------------------------------------------------ #
    getdents_idx = find_getdents_non_compat(lines)
    if getdents_idx is None:
        print(
            "[error] fix_readdir: non-compat SYSCALL_DEFINE3(getdents, ...) not found — "
            "upstream readdir.c may have changed!",
            file=sys.stderr,
        )
        sys.exit(1)

    # Search within a generous window after getdents_idx — dynamic enough
    # to handle upstream readdir.c growing without hardcoded line limits
    SEARCH_WINDOW = 120
    window = lines[getdents_idx : getdents_idx + SEARCH_WINDOW]

    # ------------------------------------------------------------------ #
    # 3. Inject initial_count + MAGIC_POS check after fdget_pos block
    #    Pattern: fdget_pos line followed by if (!f.file)
    # ------------------------------------------------------------------ #
    fdget_rel = None
    for j, line in enumerate(window):
        if FDGET_ANCHOR in line:
            if j + 1 < len(window) and FDGET_NEXT in window[j + 1]:
                fdget_rel = j
                break

    if fdget_rel is None:
        print(
            f"[error] fix_readdir: fdget_pos anchor not found in getdents body — "
            "upstream readdir.c may have changed!",
            file=sys.stderr,
        )
        sys.exit(1)

    abs_fdget = getdents_idx + fdget_rel
    lines.insert(abs_fdget, FDGET_INJECT)

    # Recalculate window after insert
    window = lines[getdents_idx : getdents_idx + SEARCH_WINDOW]

    # ------------------------------------------------------------------ #
    # 4. Inject MAGIC_POS early-exit before iterate_dir
    #    and zeromount_inject_dents after iterate_dir
    # ------------------------------------------------------------------ #
    iterate_rel = None
    for j, line in enumerate(window):
        if ITERATE_ANCHOR in line:
            if j + 1 < len(window) and ITERATE_NEXT in window[j + 1]:
                iterate_rel = j
                break

    if iterate_rel is None:
        print(
            f"[error] fix_readdir: iterate_dir anchor not found in getdents body — "
            "upstream readdir.c may have changed!",
            file=sys.stderr,
        )
        sys.exit(1)

    abs_iterate = getdents_idx + iterate_rel

    # Insert MAGIC_POS early-exit BEFORE iterate_dir line
    lines.insert(abs_iterate, ITERATE_INJECT_BEFORE)

    # iterate_dir is now at abs_iterate + 1; insert after it
    abs_iterate_after = abs_iterate + 2
    lines.insert(abs_iterate_after, ITERATE_INJECT_AFTER)

    # Recalculate window after inserts
    window = lines[getdents_idx : getdents_idx + SEARCH_WINDOW]

    # ------------------------------------------------------------------ #
    # 5. Inject zm_out: label before fdput_pos(f)
    # ------------------------------------------------------------------ #
    zmout_rel = None
    for j, line in enumerate(window):
        if ZM_OUT_ANCHOR in line:
            zmout_rel = j
            break

    if zmout_rel is None:
        print(
            f"[error] fix_readdir: fdput_pos anchor not found in getdents body — "
            "upstream readdir.c may have changed!",
            file=sys.stderr,
        )
        sys.exit(1)

    abs_zmout = getdents_idx + zmout_rel
    lines.insert(abs_zmout, ZM_OUT_INJECT)

    # ------------------------------------------------------------------ #
    # Write result
    # ------------------------------------------------------------------ #
    with open(path, "w") as f:
        f.writelines(lines)

    print("[info] fix_readdir: ZeroMount injected into readdir.c ✅")
    sys.exit(0)


if __name__ == "__main__":
    main()
