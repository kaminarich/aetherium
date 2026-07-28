#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
#
# inject_namei.py — inject ZeroMount hooks into fs/namei.c
#
# Handles namei.c injection for every ZeroMount build (RESUKISU, SUKISU,
# KSUNEXT — ZeroMount requires SuSFS, so VANILLA is never a valid combo,
# see zeromount.sh), replacing the namei.c hunks from the ZeroMount patch,
# which are diffed against a SuSFS-patched baseline and mis-apply on a
# non-SuSFS tree (see strip_namei_hunk.py for the full explanation). The
# ZeroMount patch is pre-stripped of its namei.c hunks before being
# applied, so this worker is always the sole authority for namei.c
# injection.
#
# All anchors below are matched against real, unpatched upstream
# fs/namei.c (chainonyourdoor/LuminaireKernel-6.1,
# android14-6.1-lts) — they don't depend on SuSFS or any KSU fork
# having touched the file first, so this applies identically and
# correctly regardless of variant or patch order (baseline-agnostic by
# design, even though SuSFS is required at the addon level — see
# zeromount.sh).

import sys

IDEMPOTENCY_MARKER = "#ifdef CONFIG_ZEROMOUNT"

# --------------------------------------------------------------------- #
# 1. #include <linux/zeromount.h> — after the last file-local include,
#    before the function bodies start.
# --------------------------------------------------------------------- #
INCLUDE_ANCHOR = '#include "mount.h"'
INCLUDE_INJECT = (
    "\n"
    "#ifdef CONFIG_ZEROMOUNT\n"
    "#include <linux/zeromount.h>\n"
    "#endif"
)

# --------------------------------------------------------------------- #
# 2. zeromount_getname_hook — in getname_flags(), right before the
#    final `return result;` of its non-empty-path path. Anchored on the
#    three-line block immediately preceding that return, which is
#    unique to this function (getname_kernel() also calls
#    audit_getname(result) but with a blank line before its return and
#    without the two preceding result-> assignments).
# --------------------------------------------------------------------- #
GETNAME_ANCHOR = (
    "\tresult->uptr = filename;\n"
    "\tresult->aname = NULL;\n"
    "\taudit_getname(result);\n"
)
GETNAME_INJECT = (
    "\n"
    "#ifdef CONFIG_ZEROMOUNT\n"
    "\tif (!IS_ERR(result)) {\n"
    "\t\tresult = zeromount_getname_hook(result);\n"
    "\t}\n"
    "#endif\n"
)

# --------------------------------------------------------------------- #
# 3 & 4. Permission-check short-circuit — identical block injected at
#    the top of both generic_permission() and inode_permission(), each
#    anchored on the first real statement of that specific function
#    (unique per function, so the two can't cross-match each other).
# --------------------------------------------------------------------- #
PERMISSION_INJECT = (
    "#ifdef CONFIG_ZEROMOUNT\n"
    "\tif (zeromount_is_injected_file(inode)) {\n"
    "\t\tif (mask & MAY_WRITE)\n"
    "\t\t\treturn -EACCES;\n"
    "\t\treturn 0;\n"
    "\t}\n"
    "\n"
    "\tif (S_ISDIR(inode->i_mode) && zeromount_is_traversal_allowed(inode, mask)) {\n"
    "\t\treturn 0;\n"
    "\t}\n"
    "#endif\n"
    "\n"
)

GENERIC_PERMISSION_ANCHOR = "\tret = acl_permission_check(mnt_userns, inode, mask);\n"
INODE_PERMISSION_ANCHOR = "\tretval = sb_permission(inode->i_sb, inode, mask);\n"


def find_anchor(lines, anchor, label):
    for i, line in enumerate(lines):
        if line == anchor:
            return i
    print(
        f"[error] inject_namei: anchor for {label} not found — "
        "upstream namei.c may have changed!",
        file=sys.stderr,
    )
    sys.exit(1)


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path/to/fs/namei.c>", file=sys.stderr)
        sys.exit(1)

    path = sys.argv[1]

    with open(path, "r") as f:
        content = f.read()

    # Idempotency check
    if IDEMPOTENCY_MARKER in content:
        print("[info] inject_namei: ZeroMount already injected — skipping ✅")
        sys.exit(0)

    lines = content.splitlines(keepends=True)

    # ------------------------------------------------------------------ #
    # 1. Inject #include <linux/zeromount.h>
    # ------------------------------------------------------------------ #
    include_idx = find_anchor(lines, INCLUDE_ANCHOR + "\n", "#include \"mount.h\"")
    lines.insert(include_idx + 1, INCLUDE_INJECT + "\n")

    # Re-derive content/lines fresh after each insert to keep indices simple
    content = "".join(lines)
    lines = content.splitlines(keepends=True)

    # ------------------------------------------------------------------ #
    # 2. Inject zeromount_getname_hook in getname_flags()
    # ------------------------------------------------------------------ #
    content = "".join(lines)
    if GETNAME_ANCHOR not in content:
        print(
            "[error] inject_namei: getname_flags() anchor not found — "
            "upstream namei.c may have changed!",
            file=sys.stderr,
        )
        sys.exit(1)
    content = content.replace(GETNAME_ANCHOR, GETNAME_ANCHOR + GETNAME_INJECT, 1)

    # ------------------------------------------------------------------ #
    # 3. Inject permission short-circuit into generic_permission()
    # ------------------------------------------------------------------ #
    if GENERIC_PERMISSION_ANCHOR not in content:
        print(
            "[error] inject_namei: generic_permission() anchor not found — "
            "upstream namei.c may have changed!",
            file=sys.stderr,
        )
        sys.exit(1)
    content = content.replace(
        GENERIC_PERMISSION_ANCHOR, PERMISSION_INJECT + GENERIC_PERMISSION_ANCHOR, 1
    )

    # ------------------------------------------------------------------ #
    # 4. Inject permission short-circuit into inode_permission()
    # ------------------------------------------------------------------ #
    if INODE_PERMISSION_ANCHOR not in content:
        print(
            "[error] inject_namei: inode_permission() anchor not found — "
            "upstream namei.c may have changed!",
            file=sys.stderr,
        )
        sys.exit(1)
    content = content.replace(
        INODE_PERMISSION_ANCHOR, PERMISSION_INJECT + INODE_PERMISSION_ANCHOR, 1
    )

    with open(path, "w") as f:
        f.write(content)

    print("[info] inject_namei: ZeroMount injected into namei.c ✅")
    sys.exit(0)


if __name__ == "__main__":
    main()
