#!/usr/bin/env bash
# Fix use-before-declaration introduced by the gki-android12-5.10 susfs
# patch in fs/statfs.c.
#
# The patch adds susfs_statfs_by_dentry(), which calls
# susfs_sus_kstat_spoof_vfs_statfs(), but the extern declarations for both
# susfs_is_inode_sus_kstat() and susfs_sus_kstat_spoof_vfs_statfs() only
# appear later in the file, after vfs_get_fsid(). fs/statfs.c never
# includes susfs.h (only susfs_def.h, which declares neither), so clang
# fails the build under -Werror:
#
#   ../fs/statfs.c:88:6: error: implicit declaration of function
#   'susfs_sus_kstat_spoof_vfs_statfs' [-Werror,-Wimplicit-function-declaration]
#
# This script moves the extern declarations above the helper and drops
# the duplicate block that used to sit after vfs_get_fsid(). It is a
# no-op when the file is unpatched or already carries the fix.
set -eu

TARGET="fs/statfs.c"

[ -f "$TARGET" ] || { echo "fix-susfs-statfs: $TARGET not found, skipping"; exit 0; }
grep -q "susfs_statfs_by_dentry" "$TARGET" || { echo "fix-susfs-statfs: statfs not patched by susfs, skipping"; exit 0; }

python3 - "$TARGET" << 'PYEOF'
import re
import sys

path = sys.argv[1]
src = open(path).read()

if re.search(r"extern int susfs_sus_kstat_spoof_vfs_statfs\(struct inode \*inode, struct kstatfs \*buf, bool \*is_fuse\);\nstatic int susfs_statfs_by_dentry", src):
    print("fix-susfs-statfs: already fixed, skipping")
    sys.exit(0)

decl = ("#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n"
        "extern bool susfs_is_inode_sus_kstat(struct inode *inode, bool *out_is_fuse);\n"
        "extern int susfs_sus_kstat_spoof_vfs_statfs(struct inode *inode, struct kstatfs *buf, bool *is_fuse);\n"
        "static int susfs_statfs_by_dentry")

anchor = ("#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n"
          "static int susfs_statfs_by_dentry")

if anchor not in src:
    print("fix-susfs-statfs: anchor not found, skipping")
    sys.exit(0)

src = src.replace(anchor, decl)

# Remove the original (now duplicate) declaration block after vfs_get_fsid.
dup = re.compile(
    r"#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n"
    r"extern bool susfs_is_inode_sus_kstat\(struct inode \*inode, bool \*out_is_fuse\);\n"
    r"extern int susfs_sus_kstat_spoof_vfs_statfs\(struct inode \*inode, struct kstatfs \*buf, bool \*is_fuse\);\n"
    r"#endif // #ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n")
src, n = dup.subn("", src)
assert n <= 2, f"unexpected number of duplicate blocks: {n}"

open(path, "w").write(src)
print("fix-susfs-statfs: moved extern declarations above susfs_statfs_by_dentry")
PYEOF
